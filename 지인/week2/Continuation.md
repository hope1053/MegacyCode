## [CheckedContinuation.swift](https://github.com/swiftlang/swift/blob/ed42300cc59e86295cdbb865d0f1bf139787cc97/stdlib/public/Concurrency/CheckedContinuation.swift#L126)

```swift
public struct CheckedContinuation<T, E: Error>: Sendable {
  private let canary: CheckedContinuationCanary
  
  public init(continuation: UnsafeContinuation<T, E>, function: String = #function) {
    canary = CheckedContinuationCanary.create(
      continuation: continuation,
      function: function)
  }
```

- `CheckedContinuation`은 `UnsafeContinuation`을 감싸서 `안전성 검사`를 추가하는 래퍼 타입이다.
- 직접 이니셜라이저 호출할 필요 없으며, 
`withCheckedContinuation()` or `withCheckedThrowingContinuation()` 사용한다.
- 이미 존재하는 `UnsafeContinuation`에 안정성 검사를 추가하고 싶을 때만 직접적으로 사용한다.

**파라미터**

- continuation : 아직 resume 되지 않은 UnsafeContinuation 인스턴스
- function : 런타임 진단 메시지에서 continuation을 식별하는데 사용되는 문자열

**주의 사항**

- UnsafeContinuation을 이니셜라이저에 전달한 후에는 continuation을 직접 사용하면 안된다.
- 모든 조작은 새로 생성된 `CheckedContinuation` 인스턴스를 통해 이뤄져야 한다.

### [func resume(returning value: sending T)](https://github.com/swiftlang/swift/blob/ed42300cc59e86295cdbb865d0f1bf139787cc97/stdlib/public/Concurrency/CheckedContinuation.swift#L164)

> continuation을 통해 중단된 태스크를 재개하는 역할
> 

```swift
  public func resume(returning value: sending T) {
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

1. canary.takeContinuation()을 통해 `UnsafeContinuation`을 가져온다.
2. continuation이 존재하면 value를 반환하며 재개한다.
3. continuation이 이미 사용되었다면 (nil 반환) 치명적 오류를 발생시킨다.

### [public func withCheckedContinuation<T>()](https://github.com/swiftlang/swift/blob/ed42300cc59e86295cdbb865d0f1bf139787cc97/stdlib/public/Concurrency/CheckedContinuation.swift#L298)

> 현재 Task에 대한 checked continuation을 사용하여 전달된 클로저를 실행한다.
클로저의 본문은 호출한 Task에서 동기적으로 실행되며, 클로저가 반환되면 호출한 태스크는 일시 중단된다. Task를 즉시 재개하거나, continuation을 저장해두었다가 나중에 완료할 수 있으며, 이후 중단된 태스크가 재개된다.
> 

```swift
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

**파라미터 설명**

- isolation: Actor 격리 컨텍스트를 지정 (기본값: 현재 격리 상태)
- function: continuation을 식별하는 문자열 (기본값: 현재 함수 이름)
- body: `CheckedContinuation`을 매개변수로 받는 클로저

**내부 구현**

1. Builtin.withUnsafeContinuation을 사용하여 저수준 continuation 생성
2. UnsafeContinuation을 생성하고 이를 `CheckedContinuation`으로 래핑
3. 안전성 검사가 추가된 continuation을 클로저에 전달

---

## [UnsafeContinuation.swift](https://github.com/swiftlang/swift/blob/91d8abbc1304a5c835e3a8eec9e880562a969206/stdlib/public/Concurrency/PartialAsyncTask.swift#L483)

```swift
@frozen // ABI 안정성을 위한 속성
@unsafe // 안전하지 않은 작업을 수행힐 수 있다.
public struct UnsafeContinuation<T, E: Error>: Sendable {
    @usableFromInline internal var context: Builtin.RawUnsafeContinuation
    
    @_alwaysEmitIntoClient
    internal init(_ context: Builtin.RawUnsafeContinuation) {
        self.context = context
    }
}
```

### **CheckedContinuation과의 차이점**

`UnsafeContinuation`**의 특징**

- 런타임 검사를 수행하지 않아 오버헤드가 적다.
- 이벤트 루프, 델리게이트 메서드, 콜백 등과 Swift Task를 연결하는 저수준 메커니즘
- 성능이 중요한 상황에서 사용된다.

`CheckedContinuation`**과의 비교**

- CheckedContinuation은 런타임 검사를 수행한다.
- 두 타입은 동일한 인터페이스를 가지고 있어 대부분의 상황에서 서로 교체 가능하다.
- 개발 중에는 `CheckedContinuation`을 사용하여 올바른 사용을 검증하는 것이 좋다 `✅ 공식문서 피셜`

### [public func withUnsafeContinuation<T>](https://github.com/swiftlang/swift/blob/91d8abbc1304a5c835e3a8eec9e880562a969206/stdlib/public/Concurrency/PartialAsyncTask.swift#L687)

```swift
@available(SwiftStdlib 5.1, *)
@_alwaysEmitIntoClient
@unsafe
public func withUnsafeContinuation<T>(
  isolation: isolated (any Actor)? = #isolation,
  _ fn: (UnsafeContinuation<T, Never>) -> Void
) async -> sending T {
  return await Builtin.withUnsafeContinuation {
    fn(UnsafeContinuation<T, Never>($0))
  }
}
```

`isolation: isolated (any Actor)? = #isolation`

격리 컨텍스트 지정

- 현재 실행 중인 actor의 격리 상태를 지정합니다
- #isolation은 현재의 격리 상태를 의미합니다

안전한 상태 접근

- actor의 격리된 상태에 안전하게 접근할 수 있게 합니다
- 여러 actor 간의 상태 접근을 제어한다.

```swift
actor Employee {
    var salary: Double
    
    // actor-isolated 메서드
    func increaseSalary(amount: Double) {
        salary += amount
    }
}

// isolation 매개변수를 사용하는 함수
func giveRaise(to employee: isolated Employee, amount: Double) {
    // isolated 키워드를 사용하여 직접 접근 가능
    employee.increaseSalary(amount: amount)
}[3]
```
---

### Continuation 내부에 있는 **`Canary` 역할**

**안전성 검사**

- continuation이 정확히 한 번만 resume 되었는지 확인
- 중복 resume 호출을 감지
- resume이 누락된 경우를 감지

**오류 감지 시나리오**

- continuation이 한 번도 resume되지 않고 소멸된 경우
- continuation이 여러 번 resume된 경우
- continuation이 이미 resume된 후에 다시 사용하려고 시도하는 경우
**작동 방식**

canary는 CheckedContinuationCanary라는 내부 타입으로, continuation의 상태를 추적한다.

상태 변화를 모니터링하고, 잘못된 사용이 감지되면 런타임 에러나 경고를 발생시켜 개발자가 continuation을 올바르게 사용할 수 있도록 도와준다.

```swift
swiftprivate enum ContinuationStatus {
    case pending // continuation이 아직 resume되지 않은 상태
    case resumed // continuation이 정상적으로 resume된 상태
    case abandoned // continuation이 적절히 처리되지 않고 버려진 상태
}
```

**예제 코드**
    
```swift
//
//  DiffContinuation.swift
//  ConcurrencyPerformance
//
//  Created by Jiin Kim on 11/15/24.
//

import Foundation

actor ContinuationTester {
    // MARK: - Double Resume Tests
    func testCheckedDoubleResume() async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: "First")
                // 두 번째 resume은 크래시를 발생시킵니다
                continuation.resume(returning: "Second")
            }
        }
    }
    
    func testUnsafeDoubleResume() async -> String {
        return await withUnsafeContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: "First")
                // 두 번째 resume은 무시되고 경고 메시지가 출력됩니다
                continuation.resume(returning: "Second")
            }
        }
    }
    
    // MARK: - No Resume Tests
    
    func testCheckedNoResume() async -> String {
        return await withCheckedContinuation { continuation in
            // resume을 호출하지 않으면 메모리 릭 경고가 발생합니다
            DispatchQueue.global().async {
                // 아무 작업도 하지 않음
            }
        }
    }
    
    func testUnsafeNoResume() async -> String {
        return await withUnsafeContinuation { continuation in
            // resume을 호출하지 않으면 데드락이 발생할 수 있습니다
            DispatchQueue.global().async {
                // 아무 작업도 하지 않음
            }
        }
    }
    
    // MARK: - Performance Tests
    
    func performanceTest() async {
        let iterations = 100_000
        
        // Checked Continuation 성능 테스트
        let checkedStartTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = await withCheckedContinuation { continuation in
                continuation.resume(returning: ())
            }
        }
        let checkedDuration = CFAbsoluteTimeGetCurrent() - checkedStartTime
        
        // Unsafe Continuation 성능 테스트
        let unsafeStartTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = await withUnsafeContinuation { continuation in
                continuation.resume(returning: ())
            }
        }
        let unsafeDuration = CFAbsoluteTimeGetCurrent() - unsafeStartTime
        
        print("Performance Results:")
        print("CheckedContinuation: \(checkedDuration) seconds")
        print("UnsafeContinuation: \(unsafeDuration) seconds")
        print("Performance difference: \(((checkedDuration - unsafeDuration) / unsafeDuration) * 100)%")
    }
}

// MARK: - Test Runner

@main
struct ContinuationTestRunner {
    static func main() async {
        let tester = ContinuationTester()
        
        // MARK: - continuation이 여러 번 resume된 경우
        
        print("\n=== Double Resume Tests ===")
        do {
            let result = await tester.testCheckedDoubleResume()
            print("CheckedContinuation double resume result: \(result)")
        }
        
        do {
            let result = await tester.testUnsafeDoubleResume()
            print("UnsafeContinuation double resume result: \(result)")
        }
//        
//        // MARK: - continuation이 한 번도 resume되지 않고 소멸된 경우
        print("\n=== No Resume Tests ===")
        do {
            let result = await tester.testCheckedNoResume()
            print("CheckedContinuation no resume result: \(result)")
            //[💥: ERROR] SWIFT TASK CONTINUATION MISUSE: testCheckedNoResume() leaked its continuation!
        }
        
        do {
            let result = await tester.testUnsafeNoResume()
            print("UnsafeContinuation no resume result: \(result)")
        }
//        
//        print("\n=== Performance Test ===")
//        await tester.performanceTest()
    }
}
```

