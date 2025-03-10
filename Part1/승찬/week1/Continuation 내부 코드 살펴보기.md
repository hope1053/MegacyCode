### GCD -> Continuation, async await에서 차이점이 뭘까?
  - GCD는 작업을 큐에 넣고 나면 자동으로 스케줄링하여 처리하고, 실행 중인 특정 작업을 일시 중지하거나 다시 이어서 실행하는 기능은 없다.
  - DispatchQueue.async는 태스크 실행을 위해 큐에 맡기지만, 작업이 실행되는 도중 중지되었다가 다시 이어지도록 상태를 저장하지 않는다.
  - Continuation이 작업의 상태를 유지하고, 조건이 충족되면 다시 이어질 수 있다.
  - 즉, Continuation은 비동기 함수의 실행을 일시 중지하고, 특정 조건이 충족되면 다시 실행을 이어갈 수 있는 기능이다.
 
- Concurrency에서는 async로 메서드를 호출하면 thread의 제어권을 포기하는 suspended 현상이 발생한다.
  - 예를 들어 2번 쓰레드에서 중지되었다가, 3번 쓰레드에서 다시 동작할 수 있는 상황
  - 그렇다면 다시 제어권을 받았을 때, 어디서부터 실행할지를 아는 것 즉 상태를 알아야한다.
  - 이것을 continuation이라고 한다.
 
### CheckedContinuation.swift
```swift
@available(SwiftStdlib 5.1, *)
public struct CheckedContinuation<T, E: Error>: Sendable {
  private let canary: CheckedContinuationCanary
```

- 해당 파일의 목적은 특정 작업을 일시 중지하는 비동기 함수의 실행을 지원하고, 작업이 다시 실행될 수 있도록 한다.
- `canary` -> `CheckedContinuationCanary` 타입을 가진 프로퍼티이다.
- `canary`를 통해서 `CheckedContinuation`이 올바르게 동작하고 있는지 추적, 관리하는 역할을 한다.

```swift
public init(continuation: UnsafeContinuation<T, E>, function: String = #function) {
 canary = CheckedContinuationCanary.create(
  continuation: continuation,
  function: function)
  }
```
- `UnsafeContinuation` 객체를 받아 이를 `CheckedContinuation`으로 변환하여 사용 가능하다.
- `UnsafeContinuation`도 내부적으로 `Builtin.RawUnsafeContinuation`으로 동작하므로 `continuationd`의 핵심 상태를 나타낸다.


```swift
@usableFromInline internal var context: Builtin.RawUnsafeContinuation

@_alwaysEmitIntoClient
internal init(_ context: Builtin.RawUnsafeContinuation) {
    self.context = context
}
```


```swift
await withCheckedContinuation { continuation in
    // 비동기 작업을 수행할 위치
}

public func withCheckedContinuation<T>(
  isolation: isolated (any Actor)? = #isolation,
  function: String = #function,
  _ body: (CheckedContinuation<T, Never>) -> Void
) async -> sending T {
  return await Builtin.withUnsafeContinuation {
    let unsafeContinuation = UnsafeContinuation<T, Never>($0)
    return body(CheckedContinuation(continuation: unsafeContinuation,
                                    function: function))
  }
}
```
```swift
public func resume(returning value: T)
if let c: UnsafeContinuation<T, E> = canary.takeContinuation() {
      c.resume(returning: value)
    } else {
      #if !$Embedded
      fatalError("SWIFT TASK CONTINUATION MISUSE: \(canary.function) tried to resume its continuation more than once, returning \(value)!\n")
      #else
      fatalError("SWIFT TASK CONTINUATION MISUSE")
      #endif
    }
  }
```
```swift
await withCheckedContinuation { continuation in
    someAsyncTask { result, error in
        if let error = error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: result)
        }
    }
}
```
- `withCheckedContinuation`과 `resume`을 사용해서 작업이 멈춘 지점부터 다시 이어질 수 있도록 한다.
- 이 과정에서 중요한 것은 `continuation`이다.
- `withCheckedContinuation` 메서드 내 코드를 보면 내부적으로 `Builtin.withUnsafeContinuation`을 호출하여 `UnsafeContinuation`을 생성하고, `CheckedContinuation`이 이를 래핑하여 사용한다.
- `CheckedContinuation`의 생성자를 보면 `canary`에 할당하는 것을 알 수 있고, 해당 `canary`를 통해서 해당 함수의 유효성을 체킹한다.

- `resume` 메서드 내에서 `canary.takeContinuation()`울 통해 `continuation`이 이미 재개되었는지를 검사하여 재사용을 방지하고, 다시 사용할 수 있을 경우 `resume`을 호출해 상태를 복원하며 이어서 실행하게 되는 원리이다.

- 즉, `UnsafeContinuation`은 함수 실행이 멈춘 지점의 실행 정보(변수의 값, 스택 상태, 현재 실행 위치)를 포함하고, `resume`이 호출되기 전까지 유지한다.
```swift
@available(SwiftStdlib 5.1, *)
@frozen
@unsafe
public struct UnsafeContinuation<T, E: Error>: Sendable {
  @usableFromInline internal var context: Builtin.RawUnsafeContinuation

  @_alwaysEmitIntoClient
  internal init(_ context: Builtin.RawUnsafeContinuation) {
    self.context = context
  }
```
- `UnsafeContinuation` 내 `context`((변수의 값, 스택 상태, 현재 실행 위치))에 상태가 저장된다.
- `canary`를 통해서 `Continuation`의 유효성 체크 및 `resume`이 한번만 호출되는 것을 보장한다. `canary.takeContinuation()`

++ 스레드 할당이 어떻게 이루어지는지?
- `UnsafeContinuation` `CheckedContinuation` 상태인 `context`는 특정 스레드에 종속되지 않게 구현되었다.
- `context`는 멈췄던 상태와 위치를 저장하는 일종의 데이터 패키지이며, 다른 스레드로 재배치될 때 손실 없이 가져가는 구조이다.

++ 그렇다면 어떤 원리로 스레드 할당이 이루어지는지?
- 랜덤으로 배치되는 것이 아니라 현재 시스템의 자원 상태와 스케줄링 정책에 따라 할당된다.
- 스케줄링할 때 우선순위와 작업의 부하 상태를 고려하여 적절히 스레드를 할당한다. 

https://github.com/swiftlang/swift/blob/0d7054b6377ab6b3d0e040f46d3a6bf53a8e36f3/stdlib/public/Concurrency/PartialAsyncTask.swift#L483
https://github.com/swiftlang/swift/blob/0d7054b6377ab6b3d0e040f46d3a6bf53a8e36f3/stdlib/public/Concurrency/CheckedContinuation.swift#L126
