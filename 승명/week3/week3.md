# Swift Concurrency 3주차

## sending

```Swift
public func resume(with result: sending Result<T, E>)
```

- Swift 6에 새롭게 추가된 개념으로, 함수 매개변수와 반환값이 안전하게 서로 다른 격리 경계를 넘을 수 있도록 한다.
- 함수의 매개변수 또는 결과에 sending 주석을 추가하고, 해당 값이 함수 경계를 넘어 안전하게 전송될 수 있음을 명시한다.
- sending으로 지정된 매개변수는 함수 호출 후 호출자에게 더 이상 사용되지 않아야 하며, 이는 데이터 경쟁을 방지한다.
- sending 값의 개념은 특히 non-Sendable 타입의 값을 동시성 컨텍스트 간에 안전히 전송할 수 있게 해주는 것이 핵심이다.

## inout sending
- inout으로 지정된 매개변수에 sending을 추가하면, 함수 내부에서 이 값을 수정할 수 있지만, 호출자 측에서는 해당 값에 접근할 수 없다.
- 이는 함수가 매개변수를 안전하게 수정하고, 외부의 데이터 경쟁 없이 작업할 수 있도록 보장한다.

```Swift
class NonSendable {
    var name: String
    
    init(name: String) {
        self.name = name
    }
}

@MainActor
func acceptSend(_ ns: sending NonSendable) {
    print(ns.name)
}

func sendToMain() async {
    var ns = NonSendable(name: "abcd")

    // error: sending 'ns' may cause a race
    // note: 'ns' is passed as a 'sending' parameter to 'acceptSend'. Local uses could race with
    //       later uses in 'acceptSend'.
    await acceptSend(ns)

    // note: access here could race
    ns.name = "test1"
    print(ns.name)
}
```

- Sendable 타입이면 에러가 발생하지 않음

```Swift
class NonSendable: @unchecked Sendable {}
// or
struct NonSendable {}

@MainActor
func acceptSend(_ ns: sending NonSendable) {
    print(ns.name)
}

func sendToMain() async {
    var ns = NonSendable(name: "abcd")

    // error: sending 'ns' may cause a race
    // note: 'ns' is passed as a 'sending' parameter to 'acceptSend'. Local uses could race with
    //       later uses in 'acceptSend'.
    await acceptSend(ns)

    // note: access here could race
    ns.name = "test1"
    print(ns.name)
}
```

```Swift
@MainActor
struct S {
  let ns: NonSendable

  func getNonSendableInvalid() -> sending NonSendable {
    // error: sending 'self.ns' may cause a data race
    // note: main actor-isolated 'self.ns' is returned as a 'sending' result.
    //       Caller uses could race against main actor-isolated uses.
    return ns
  }

  func getNonSendable() -> sending NonSendable {
    return NonSendable() // okay
  }
}
```

### 사용이유
- 명시성
    - 코드 가독성 향상: sending 키워드를 사용하면 해당 매개변수가 다른 스레드나 격리된 지역으로 안전하게 전송될 수 있음을 명확하게 나타낸다. 이는 코드의 의도를 분명히 하여 다른 개발자가 코드를 이해하는 데 도움을 줄 수 있다.
- 타입 안정성 강조 
    - Sendable 요구 사항: sending을 사용하면 해당 매개변수가 Sendable 타입이어야 함을 명시적으로 요구합니다. 이는 코드 작성자가 어떤 타입이 안전한지, 어떤 타입이 그렇지 않은지를 이해하는 데 도움을 줍니다.
- 잠재적 오류 방지: 
    - 경쟁 조건 방지: 비록 sending 키워드를 사용하더라도, 해당 매개변수가 NonSendable일 경우 Swift는 여전히 잠재적인 경쟁 조건을 감지하여 경고를 제공합니다. 이는 개발자가 잘못된 타입을 사용하고 있다는 것을 알리는 중요한 피드백입니다.

---

## 격리 경계
- "격리 경계"란 Swift의 동시성 모델에서 중요한 개념으로, 데이터의 안전한 접근과 수정이 이루어지는 경계를 의미한다. 이를 통해 멀티스레드 환경에서 데이터 경합이나 충돌을 방지할 수 있다.

### 1. 데이터 격리
- 격리 경계는 특정 데이터나 상태가 여러 스레드에 의해 동시에 접근되지 않도록 하는 경계를 설정한다.
- 이 경계를 넘는 데이터는 안전하게 공유될 수 없으며, 각 스레드는 자신의 격리된 상태에만 데이터를 수정하고 사용할 수 있다.

### 2. Sendable과 Non-Sandable
- Sendable: 이 타입의 데이터는 안전하게 다른 스레드로 전송될 수 있다. 즉, 격리 경계를 넘는 것이 혀용된다.
- Non-Sendable: 이 타입의 데이터는 격리 경계를 넘을 수 없으며, 해당 데이터는 특정 스레드 내에서만 안전하게 사용될 수 있다.

### 3. 동시성 안전성
- 격리 경계를 통해 데이터의 일관성과 안전성을 유지하며, 동시성 프로그래밍에서 발생할 수 있는 문제(ex. 데이터 레이스)를 최소화 할 수 있다. 

---

## 구조적 동시성과 병렬(동시)처리

### async let
- Top-Level에 선언 불가
- 비동기 함수 안에서 선언해야한다.

```Swift
async let top = ... // error: 'async let' in a function that does not support concurrency

func sync() { // note: add 'async' to function 'sync()' to make it asynchronous
  async let x = ... // error: 'async let' in a function that does not support concurrency
}

func syncMe(later: () -> String) { ... }
syncMe {
  async let x = ... // error: invalid conversion from 'async' function of type '() async -> String' to synchronous function type '() -> String'
}
```

### TaskGroup
- withTaskGroup, withDiscardingTaskGroup 등을 사용하여 구조적으로 병렬처리 가능하다.
- withDiscardingTaskGroup, withThrowingDiscardingTaskGroup를 사용해 자식 작업이 에러를 던질 수도 있다.
- withTaskGroup의 파라미터
    - of: 자식작업들에서 리턴하게되는 데이터 타입
    - returning: 부모작업에서 실질적으로 리턴하게되는 데이터 타입, (생략해도 타입 추론을 해준다)
    - body: TaskGroup이라는 부모작업 closure 제공

```Swift
let resultImageArray = await withTaskGroup(of: UIImage?.self, returning: [UIImage].self) { group in
    let url = "https://picsum.photos/1000"

    // 부모 작업에 자식 작업을 추가하는 방법
    group.addTask {
        let image = await fetchImage(urlString: url)
        return image
    }
    group.addTask {
        let image = await fetchImage(urlString: url)    
        return image
    }
    
    // 반복문을 사용해서 생성도 가능, 비동기 반복문이 아니고 Task로 감싸지 않는것을 주의
    for url in urlArray {
        group.addTask {  /// 작업을 기다리는게 아니라, 바로 다음 반복주기로 이동
            let image = await fetchImage(urlString: url)
            return image
        }
    }
    
    var imageArray: [UIImage] = []
    
    for await image in group {
        if let image = image{
            imageArray.append(image)
        }
    }
    
    return imageArray
}

return resultImageArray
```

```Swift
// 일반적인 상황
// Set up the job flags for a new task.
let flags = taskCreateFlags(
    priority: priority, 
    isChildTask: false, 
    copyTaskLocals: true,
    inheritContext: true, 
    enqueueJob: true,
    addPendingGroupTaskUnconditionally: false,
    isDiscardingTask: false
)

// Create the asynchronous task.
let builtinSerialExecutor = Builtin.extractFunctionIsolation(operation)?.unownedExecutor.executor

let (task, _) = Builtin.createTask(
    flags: flags,
    initialSerialExecutor: builtinSerialExecutor,
    operation: operation
)

self._task = task

// 그룹을 만들 때
let flags = taskCreateFlags(
    priority: nil, 
    isChildTask: true, 
    copyTaskLocals: false,
    inheritContext: false, 
    enqueueJob: true,
    addPendingGroupTaskUnconditionally: true,
    isDiscardingTask: false
)

// Create the task in this group.
let builtinSerialExecutor = Builtin.extractFunctionIsolation(operation)?.unownedExecutor.executor
_ = Builtin.createTask(
    flags: flags,
    initialSerialExecutor: builtinSerialExecutor,
    taskGroup: _group,
    operation: operation
)
```

### 비동기 반복문
- 반복문을 비동기적으로 동작시키겠다는 의미 (순차적)
- 반복문에서 동작할 수 있는 데이터 타입이 있는데 이 데이터들이 비동기적으로 나중에 생긴다는 의미
- 자식은 각자의 스레드에서 동작하지만 완료된 작업들을 모을 때는 하나의 스레드에서 동작하여 레이스 컨디션 같은 문제들까지 자동으로 해결을 해준다
- group.waitForAll() -> 사용할 필요 없음. for await 반복문이 어차피 다 기다림

```Swift
for await image in group {
    if let image = image{
        imageArray.append(image)
    }
}
```

```Swift
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
@backDeployed(before: macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0)
public mutating func next(
    isolation: isolated (any Actor)? = #isolation
) async -> ChildTaskResult?
    
// 이러한 방법으로도 가능
while let image = await group.next() {
    if let image = image {
        imageArray.append(image)
    }
}
```

### Task.detached에서 self를 명시적으로 캡쳐해야하는 이유
- Task의 경우 전달된 클로저가 즉시 실행되며 클로저의 실행이 종료되면 바로 릴리즈된다. 이 때문에 self를 캡쳐해도 메모리 누수의 위험이 적으며 그렇게 때문에 self.의 명시적인 사용을 요구하지 않는다.
- @_implicitSelfCapture 라는 어트리뷰트가 있어서 self를 생략 가능하도록 할 수 있다.
- Task.detached는 @_implicitSelfCapture 어트리뷰트가 없는걸 확인 가능

```Swift
// Task
@discardableResult
@_alwaysEmitIntoClient
public init(
    priority: TaskPriority? = nil,
    @_inheritActorContext @_implicitSelfCapture operation: sending @escaping @isolated(any) () async throws -> Success
) { ... }

// Task.detached
@discardableResult
@_alwaysEmitIntoClient
public static func detached(
    priority: TaskPriority? = nil,
    operation: sending @escaping @isolated(any) () async -> Success
) -> Task<Success, Failure> { ... }
```
