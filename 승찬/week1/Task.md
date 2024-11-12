1. 왜 GCD -> Task로 넘어간 것일까?
2. 메타데이터가 무엇일까?
3. Task는 왜 struct로 구현되어 있을까?
4. Task struct에 @frozen이 사용된 이유?
5. 아래 코드에서 taskA를 취소하면 taskB도 취소가 되는데 Task가 참조처럼 동작하는 이유가 무엇일까?
6. Builtin.NativeObject

```swift
 let taskA = Task {
        print("Task A 시작")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        print("Task A 완료")
        return "결과 값"
    }
 let taskB = taskA

        print("taskA 상태: \(taskA.isCancelled ? "취소됨" : "실행 중")")
        taskA.cancel()

        print("taskB 상태: \(taskB.isCancelled ? "취소됨" : "실행 중")")

        Task {
            do {
                let result = try await taskB.value
                print("taskB의 결과: \(result)")
            } catch {
                print("taskB가 취소됨: \(error.localizedDescription)")
            }
        }
```
<img width="782" alt="스크린샷 2024-11-07 오후 7 42 48" src="https://github.com/user-attachments/assets/817fb960-0ed6-4666-91e0-426c9bb2379c">

- taskA.cancel() -> taskB도 cancel

```swift
@available(SwiftStdlib 5.1, *)
@frozen
public struct Task<Success: Sendable, Failure: Error>: Sendable {
  @usableFromInline
  internal let _task: Builtin.NativeObject

  @_alwaysEmitIntoClient
  internal init(_ task: Builtin.NativeObject) {
    self._task = task
  }
}
```

`@frozen`
- 구조체의 내부 메모리 레이아웃이 고정되어 있음을 의미
- 추후 버전에서 멤버 변수를 추가하거나 제거할 수 없다는 것을 의미

`ABI 안정성`
- ABI는 프로그램이 이진 형태로 컴파일된 후에도 다른 모듈과 상호작용할 수 있도록 해주는 규칙
- Swift에서는 새로운 Swift 버전에서도 동일한 방식으로 컴파일 된다는 것을 의미

`메모리 레이아웃`
- 구조체, 클래스, 열거형 등의 데이터 타입이 메모리에 배치되는 방식
- Swift 컴파일러는 데이터 타입의 필드들을 특정한 순서와 방식으로 메모리에 배치하여 접근성과 성능을 최적화

`internal let _task: Builtin.NativeObject`

- 내부 속성으로, Swift 런타임이 작업을 추적하는 데 사용하는 기본 객체
- 이 속성은 Task의 실제 작업을 나타내는 핵심 데이터

### 왜 Task는 구조체로 구현이 되어있을까?:
- Task 자체는 태스크에 대한 메타데이터와 핸들을 제공하는 객체이다.
- 필요할 때 값 타입으로 빠르게 복사할 수 있어 메모리 관리와 성능 최적화에 유리

- 참조할 데이터는 내부적으로 관리
  - Task는 내부적으로 Builtin.NativeObject를 사용하여 태스크의 상태나 데이터를 관리한다.
  - 이 객체는 @frozen으로 안정성을 유지하며, 실제 태스크의 상태 관리는 네이티브 객체에 의해 수행되기 때문에 Task 구조체가 복사되더라도 참조 관리에 부담을 주지 않는다.
  - Swift의 구조체는 참조 횟수를 관리하지 않으므로, 참조 타입(class)보다 관리 부담이 줄어든다.

- 값 타입 특성으로 안전한 복사
  - Task는 특정 태스크에 대한 상태나 제어 정보를 포함하며, 이러한 정보가 다른 컨텍스트에서 **동일한 값을 유지한 채 안전하게 복사**될 수 있다.
  - 복사된 각 Task 인스턴스는 동일한 태스크를 나타내므로, 참조 타입이 아닌 값 타입(struct)으로 구현하면 의도치 않은 참조 공유나 상태 변경을 방지할 수 있다.
  
- 간결한 메모리 관리
   - Task는 Swift의 **Sendable** 프로토콜을 준수하여 스레드 간에 안전하게 전달될 수 있다.
   - 참조 타입인 class는 ARC에 의해 메모리 관리가 필요하지만, 값 타입은 이와 같은 관리가 필요 없어 더욱 효율적이다.

### 메타데이터
- Task 구조체는 실행 상태를 조작하거나 추적할 수 있도록 하는 접근 포인트를 제공한다.
- Task를 통해 태스크의 취소 상태를 확인하거나, 태스크가 완료될 때 결과를 기다리는 등의 작업을 할 수 있다.
- 하지만 Task 자체가 실제 태스크의 모든 데이터를 포함하지 않고, 실제 작업을 수행하는 태스크에 대한 참조를 가진다. 이 참조가 바로 내부의 `_task: Builtin.NativeObject` 이다.

- 메타데이터는 태스크의 속성 정보를 의미한다.
- Task가 현재 실행 중인지, 취소되었는지, 완료되었는지와 같은 상태 정보 등이 메타데이터이다.
- 실제 태스크는 내부 BuiltIn.NativeObject로 제어한다.

### 그럼 어떻게 동작을 하는지?
1. Task가 시작되면, 해당 작업이 비동기적으로 실행된다.
2. 생성된 Task를 참조하지 않더라도 해당 작업은 계속 진행됩니다. 하지만 참조를 놓치게 되면, 그 작업의 결과를 기다리거나 취소할 수 있는 권한을 잃게 된다.
3.  한 Task 인스턴스를 취소하면 그 Task의 다른 복사본에도 영향을 미친다.

- 구조체보다는 클래스처럼 동작하는데 `Builtin.NativeObject` 을 통해서 동작한다.

```swift
public var result: Result<Success, Failure> {
  get async {
      do {
        return .success(try await value)
      } catch {
        return .failure(error as! Failure) // as!-safe, guaranteed to be Failure
      }
    }
  }

public var value: Success {
    get async throws {
      return try await _taskFutureGetThrowing(_task)
    }
  }
public func cancel() {
    Builtin.cancelAsyncTask(_task)
  }
```
```swift
@available(SwiftStdlib 5.1, *)
@_silgen_name("swift_task_future_wait_throwing")
public func _taskFutureGetThrowing<T>(_ task: Builtin.NativeObject) async throws -> T
```

https://forums.swift.org/t/why-is-task-a-struct-when-it-acts-so-much-more-like-a-reference-type/61970/22
