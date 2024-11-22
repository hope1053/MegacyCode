## Swift는 구조화된 방식으로 비동기와 병렬 코드 작성을 지원한다.

### 구조화된 동시성 (structured concurrency Vs unstructured concurrency)

- 비동기 코드
    - **일시적으로 중단되었다가 다시 실행할 수 있지만 한번에 프로그램의 한 부분만 실행된다.**
    - **프로그램에서 코드를 일시 중단하고 다시 실행하면 UI 업데이트와 같은 짧은 작업을 계속 진행하면서 네트워크를 통해 데이터를 가져오거나 파일을 분석하는 것과 같은 긴 실행 작업을 계속할 수 있다.**
- 병렬 코드
    - 동시에 코드의 여러부분이 실행됨을 의미한다.
    - 예를 들어 4코어 프로세서의 컴퓨터는 각 코어가 하나의 작업을 수행하므로 코드의 4부분을 동시에 실행할 수 있다.

> Swift 에서 동시성 모델은 쓰레드의 최상단에 구축되지만 직접적으로 상호작용하지 않는다.

* 쓰레드의 최상단에 구축되지만 직접적으로 상호작용하지 않는다는 것은 개발자가 직접 쓰레드를 관리할 필요가 없다는 의미이다.
> 

https://developer.apple.com/kr/videos/play/wwdc2021/10134/

++ 구조화된 동시성과 비구조화된 동시성 WWDC 내용 요약 

https://zeddios.tistory.com/1389

++ 제드님 블로그

https://developer.apple.com/kr/videos/play/wwdc2022/110350/

https://ios-adventure-with-aphelios.tistory.com/23

### Instruments를 활용한 Task Group 생성

- 부모 작업과 자식 작업의 관계를 Instruments를 통해 살펴본다.

```swift
 @objc private func runParallelSum() {
        Task {
            let result = await calculateParallel()
            print("✅ 결과: \(result)")
        }
    }
    
    private func calculateParallel() async -> Int {
        let chunkSize = 20_000
         print("👨 부모 Task 시작: \(Thread.current)")
         
         return await withTaskGroup(of: Int.self) { group in
             // 자식 Task 생성
             for i in stride(from: 0, to: 100_000, by: chunkSize) {
                 group.addTask {
                     print("👶 자식 Task \(i/chunkSize) 시작: \(Thread.current)")
                     
                     var sum = 0
                     let end = min(i + chunkSize, 100_000)
                     for j in i...end {
                         sum += j
                     }
                     
                     let result = sum
                     print("👶 자식 Task \(i/chunkSize) 결과: \(result)")
                     return result
                 }
             }
             
             print("👨 부모 Task:  자식 Task 기다리는 중")
             var totalSum = 0
             for await partialSum in group {
                 totalSum += partialSum
             }
             print("👨 부모 Task 완료 및 결과: \(totalSum)")

             return totalSum
         }
    }
```
<img width="703" alt="스크린샷 2024-11-21 오후 7 33 03" src="https://github.com/user-attachments/assets/3f37a41e-7236-4c90-a070-c5bd13387e27">



> 해당 코드를 Instruments를 통해 살펴보면 맨 아래 부모 Task가 실행되고 그 위에 자식 Task가 생성되며 동작하는 것을 볼 수 있다.

> 부모 Task는 자식 Task들이 완료되는 것을 기다리는 것을 아래의 Instruments 사진을 통해 확인할 수 있다.

> 코드 상에 동작을 보면 자식 Task는  실행과 완료되는 순서는 무작위이다. 그 이유는 각 자식 Task들은 각각 다른 스레드에서 병렬로 실행되기 때문이다.
> 

<img width="711" alt="스크린샷 2024-11-21 오후 7 33 16" src="https://github.com/user-attachments/assets/4ab56e92-7575-4381-a8e9-a8937f283169">

> 그렇다면 코드상에서는 Thread 3, 8, 9, 10, 11 총 다섯개에서 자식 작업을 수행했는데, Instruments 상에서도 과연 그럴까 테스트해보았다.

++ 위의 캡쳐본을 통해 얘기하겠다..
> 

> 자식 Task가 Running 상태일 때, Thread State Trace를 보았다.

`Task0x1`  `Task0x2`  `Task0x3`  `Task0x4`  `Task0x5`  `Task0x6`

`Task0x1`은 버튼을 클릭했을 때 불리는 함수이고, 나머지는 `Task`는 자식 Task라고 생각하면 된다.

`Task0x1`는 `Main Thread`에서 동작한다. 그럼 이제 봐야 할 것이 각 자식 Task는 어떤 스레드에서 동작하는지 살펴봐야 한다.

가장 맨위 `Task0x2` 먼저 보면 `2번 스레드`에서 동작하는 걸 볼 수 있다. (편의상)

`Task0x3 7번 스레드` `Task0x4 7번 스레드` `Task0x5 2번 스레드` `Task0x6 7번 스레드` 동작한다.
> 

<img width="708" alt="스크린샷 2024-11-21 오후 7 33 44" src="https://github.com/user-attachments/assets/22e0f636-3246-46e4-8232-c2ce1d0bb62b">

> 중요한 것은 각 작업이 GCD와 달리 독립적인 스레드에서 동작한 것이 아니라 여러 작업들이 하나의 스레드에서 동작했다는 것이다.

> 한 번 더 빌드해서 확인해보면 하나의 Task 당 하나의 스레드를 만들지 않고, 기존 다른 작업이 사용하고 있던 스레드에서 Task들이 실행되는 것을 확인할 수 있다. (새로 생성되는 경우 제외)

> 하나의 스레드에 작업이 할당된 상태에서 `await` 키워드를 만나면 작업의 결과를 기다리는동안 다른 작업에 스레드를 사용할수 있게 한다.

> 아래 GCD 사진과 비교했을 때, 스레드를 확실히 효율적으로 사용하고 있는 것이 보인다.
> GCD에서는 모든 작업에 대해 스레드를 생성해서 사용하고 있다.
> 
<img width="708" alt="스크린샷 2024-11-21 오후 7 33 56" src="https://github.com/user-attachments/assets/880d7fb9-432f-449d-ade7-e78cce1ad287">


> 즉, 아래와 같이 정리할 수 있다.
> 
> - **GCD**
>     - 시스템이 관리하는 스레드 풀 사용한다.
>     - 작업마다 다른 스레드 할당 가능하다.
>     - 스레드 수를 직접 제어하지 않는다.
> - **TaskGroup**:
>     - Swift 런타임이 최적화된 방식으로 관리한다.
>     - 작업이 같은 스레드에서 실행될 수 있다.
>     - continuation 기반 동시성 활용한다.

### 부모는 자식들의 작업을 기다리는데 어떤 원리로 기다리는 것일까?

> Instruments를 보면 부모의 Task가 Creating 되고 자식들의 Task가 Creating ~ Running 과정을 거치고 마지막에 부모 Task가 Running~Suspend을 반복하는 것을 볼 수가 있다.

> 그렇다면 어떤 원리로 부모는 자식들의 작업을 기다릴 수 있는 것일까?

> 아래의 코드를 먼저 살펴보자.


```swift
await withTaskGroup(of: Void.self) { group in
    group.addTask { ..doSomething.. }
} 
```

> `TaskGroup`을 생성할 때, 대게 위와 같은 코드를 사용할 것이다.

해당 코드의 내부를 살펴본다면 부모가 자식들의 작업을 어떻게 기다리는지 알 수 있을 것 같아,, 살펴보겠다.
> 

### withTaskGroup

```swift
@available(SwiftStdlib 5.1, *)
#if !hasFeature(Embedded)
@backDeployed(before: SwiftStdlib 6.0)
#endif
@inlinable
public func withTaskGroup<ChildTaskResult, GroupResult>(
  of childTaskResultType: ChildTaskResult.Type = ChildTaskResult.self,
  returning returnType: GroupResult.Type = GroupResult.self,
  isolation: isolated (any Actor)? = #isolation,
  body: (inout TaskGroup<ChildTaskResult>) async -> GroupResult
) async -> GroupResult {
  #if compiler(>=5.5) && $BuiltinTaskGroupWithArgument

  let _group = Builtin.createTaskGroup(ChildTaskResult.self)
  var group = TaskGroup<ChildTaskResult>(group: _group)

  // Run the withTaskGroup body.
  let result = await body(&group)

  await group.awaitAllRemainingTasks()

  Builtin.destroyTaskGroup(_group)
  return result

  #else
  fatalError("Swift compiler is incompatible with this SDK version")
  #endif
}
```

> 제네릭 타입으로 `ChildTaskResult` `GroupResult`를 사용한다.

`ChildTaskResult`는 말그대로 `자식 Task`들이 가지는 타입을 말하고, `GroupTask`는 return 되는 것의 타입을 말한다.
> 

```swift
let numbers = await withTaskGroup(of: Int.self) { group in
    // 각 자식 태스크는 Int 반환
    group.addTask { return 1 }
    group.addTask { return 2 }
    
    // 그룹의 최종 결과는 [Int]
    var results: [Int] = []
    for await num in group {
        results.append(num)
    }
    return results
}
```

```swift
 	let _group = Builtin.createTaskGroup(ChildTaskResult.self)
  var group = TaskGroup<ChildTaskResult>(group: _group)

  // Run the withTaskGroup body.
  let result = await body(&group)

  await group.awaitAllRemainingTasks()

  Builtin.destroyTaskGroup(_group)
  return result
```

> `_group`에 `자식 Task`의 타입을 가지는 것을 선언한다.
> 해당 그룹으로 `TaskGroup` 생성 시, 할당한다.

> 그리고 `body 클로저`를 실행한다.

> 남은 태스크는 대기하고, 정리한다.

> 마지막으로 결과가 반환된다.
> 

> `body`는 사용자가 정의한 작업을 실행한다. 다만 `inout 파라미터`로 그룹이 수정 가능함을 의미한다.

> **남은 태스크가 대기한다는 것은 모든 자식 태스크 완료가 보장됨을 의미한다.**

> **즉, 모든 자식 Task가 끝날 때까지 기다림을 의미한다.**

> 마지막으로 그룹 리소스 정리를 하며 메모리에서 해제된다.

> **이를 통해 구조화된 동시성을 제공하고, 모든 자식 Task의 완료를 보장한다.**
> 

*++ inout이 필요한 이유는 무엇일까?*

```swift
// group이 inout 파라미터로 전달됨
await withTaskGroup(of: Int.self) { group in
    group.addTask { return 1 }  // 그룹에 태스크 추가
    group.addTask { return 2 }  // 다른 태스크 추가
}

// 만약 inout이 없다면?
await withTaskGroup(of: Int.self) { group in
    group.addTask { return 1 }  // ❌ 오류: group은 수정 불가
}
```

> **독립적인 자식 Task를 생성하기 위해 inout을 사용한 것이다.**
> 

### TaskGroup

```swift
@available(SwiftStdlib 5.1, *)
@frozen
public struct TaskGroup<ChildTaskResult: Sendable> {

  /// Group task into which child tasks offer their results,
  /// and the `next()` function polls those results from.
  @usableFromInline
  internal let _group: Builtin.RawPointer

  // No public initializers
  @inlinable
  init(group: Builtin.RawPointer) {
    self._group = group
  }
```

> `TaskGroup`의 내부 코드를 살펴보면서 유추해보자.

> `let _group: Builtin.RawPointer` 해당 프로퍼티가 큰 역할을 하는 것 같다.
> 

```swift
 public mutating func addTask(
    priority: TaskPriority? = nil,
    operation: sending @escaping @isolated(any) () async throws -> ChildTaskResult
  ) {
    let flags = taskCreateFlags(
      priority: priority, isChildTask: true, copyTaskLocals: false,
      inheritContext: false, enqueueJob: true,
      addPendingGroupTaskUnconditionally: true,
      isDiscardingTask: false
    )

    // Create the task in this group.
    let builtinSerialExecutor =
      Builtin.extractFunctionIsolation(operation)?.unownedExecutor.executor
    _ = Builtin.createTask(flags: flags,
                           initialSerialExecutor: builtinSerialExecutor,
                           taskGroup: _group,
                           operation: operation)
  }
```

> 해당 addTask 메소드는 부모 Task에 자식 Task를 추가할 때 사용하는 메소드인데 return 값이 `ChildTaskResult`이다. 

> 해당 ChildTaskResult swift language 에서 찾아보면 구현체는 나오지 않고, 내부적으로 구현되어 있는 것을 알 수가 있는데, 아래의 코드를  제네릭 타입 파라미터인 것을 알 수 가 있다.

> 예를 들어 `withTaskGroup`이 Int라면 `ChildTaskResult`가 Int, String이라면 String을 반환한다.
> 

```swift
  // T.self
  builder.addParameter(makeMetatype(makeGenericParam(0))); // 1 ChildTaskResult.Type
```

> 다시 돌아가 `flags`부터 살펴보면 해당 `flags`는 자식 태스크를 생성할 때 사용되는 것들이다.
> 

```swift
let flags = taskCreateFlags(
    priority: priority,           // 지정된 우선순위
    isChildTask: true,           // 자식 태스크임을 표시
    copyTaskLocals: false,       // 태스크 로컬 값 복사하지 않음
    inheritContext: false,        // 컨텍스트 상속하지 않음
    enqueueJob: true,            // 작업 큐에 즉시 추가
    addPendingGroupTaskUnconditionally: true,  // 무조건적으로 그룹에 추가
    isDiscardingTask: false      // 결과를 버리지 않음
)
```

> **`isChildTask`에서 addTask가 호출될 때 해당 Task가 자식 Task임을 보장한다.**

> `copyTaskLocals`는 태스크 로컬 값들을 새 태스크에 복사할지 여부이다.

> 해당 값은 항상 false인데 그 이유는 간단히 말하면 값 복사는 오버헤드를 발생시키고, TaskGroup의 자식 태스크들은 독립적인 작업을 실행해야 하므로 값 복사를 막는 것이다.

> `inheritContext` 값은 true 라고 생각했다. 그 이유는 부모 Task의 Context를 상속받는다고 생각했기 때문이다.

> 이 부분에서 오해한 것이 addTask에서는 독립성을 보장하고 각 태스크가 독립적인 Context를 가진다.
> 즉, withTaskGroup에서는 Context 상속 (찾아봐야함)이 되고 addTask는 별개의 Context를 가진다.
> **이렇게 되면 병렬 실행이 더 효율적으로 동작하며 각 태스크가 자신만의 리소스를 관리할 수 있게 된다.**
> 

++ https://medium.com/@gangwoon/tasklocal-%ED%99%9C%EC%9A%A9-d32653021fac

> 그럼 해당 flags 값은 어디에 사용될까?

```swift
 // Create the task in this group.
    let builtinSerialExecutor =
      Builtin.extractFunctionIsolation(operation)?.unownedExecutor.executor
    _ = Builtin.createTask(flags: flags,
                           initialSerialExecutor: builtinSerialExecutor,
                           taskGroup: _group,
                           operation: operation)
```

> `extractFunctionIsolation`는 번역해보면 `작업 격리 추출`
> `unownedExecutor`는 `소유권 없는 실행자`
> `executor`는 `실행자를` 의미한다.

> `Builtin` 파일은 내부 코드의 동작을 볼 수 없기 때문에 유추해보자면 ..

> 주석을 보면 해당 그룹에 task를 생성한다는 의미이니 `Builtin`을 작업을 실제로 실행하는 관리자라고 생각하면 될 것 같다.

> **flags를 통해 작업을 설정하고,
> initialSerialExecutor을 통해 실행 관리자를 할당하고,
> taskGroup에 _group을 통해 소속될 그룹을 정하고,
> operation (클로저)을 통해 실제 실행할 코드를 선언한다.**

> 이런 원리로 addTask는 독립성을 보장하게 된다. (자체 Executor)
> 

### 흐름도 정리

```swift
@inlinable
public func withTaskGroup<ChildTaskResult, GroupResult>(
    of childTaskResultType: ChildTaskResult.Type,
    returning returnType: GroupResult.Type,
    body: (inout TaskGroup<ChildTaskResult>) async -> GroupResult
) async -> GroupResult {
    // 1. TaskGroup 생성
    let _group = Builtin.createTaskGroup(ChildTaskResult.self)
    var group = TaskGroup<ChildTaskResult>(group: _group)
    
    // 2. 사용자 정의 body 실행
    let result = await body(&group)
    
    // 3. 남은 태스크 대기
    await group.awaitAllRemainingTasks()
    
    // 4. 정리 및 결과 반환
    Builtin.destroyTaskGroup(_group)
    return result
}

@frozen
public struct TaskGroup<ChildTaskResult: Sendable> {
    // 내부 그룹 저장
    @usableFromInline
    internal let _group: Builtin.RawPointer
    
    // 초기화
    @inlinable 
    init(group: Builtin.RawPointer) {
        self._group = group
    }
}

public mutating func addTask(
    priority: TaskPriority? = nil,
    operation: @escaping () async -> ChildTaskResult
) {
    // 1. 태스크 생성 플래그 설정
    let flags = taskCreateFlags(
        priority: priority, 
        isChildTask: true,
        copyTaskLocals: false,
        inheritContext: false,
        enqueueJob: true,
        addPendingGroupTaskUnconditionally: true,
        isDiscardingTask: false
    )
    
    // 2. 실행자 추출
    let builtinSerialExecutor = 
        Builtin.extractFunctionIsolation(operation)?.unownedExecutor.executor
    
    // 3. 태스크 생성 및 그룹에 추가
    _ = Builtin.createTask(
        flags: flags,
        initialSerialExecutor: builtinSerialExecutor,
        taskGroup: _group,
        operation: operation
    )
}
```

> 1. **withTaskGroup 호출
> ↓**
> 2. **Builtin.createTaskGroup으로 그룹 생성
> ↓**
> 3. **TaskGroup 구조체 초기화
> ↓**
> 4. **사용자의 body 클로저 실행
> ↓**
> 5. **addTask 호출**
  
  > - Task 플래그 설정

  > - 실행자 추출

  > - Builtin.createTask로 태스크 생성

  >   ↓
     
> 6. **모든 태스크 완료 대기
> ↓**
> 7. **그룹 정리 및 결과 반환**
