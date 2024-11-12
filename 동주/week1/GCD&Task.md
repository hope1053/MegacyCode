## GCD 기본 개념

- `GCD`는 모든 작업을 `Queue`에 추가한다.
- `Queue`에는 `Serial Queue`와 `Concurrent Queue` 두 종류가 있다.
    - `Serial Queue`는 하나의 작업씩 순서대로 작업을 처리한다. 앞의 작업이 완료되지 않았다면 다음 작업을 실행할 수 없다.
    - `Concurrent Queue`는 여러 작업을 동시에 실행할 수 있다. 앞의 작업이 완료되지 않았더라도 다음 작업을 실행할 수 있다.
- 시스템에서는 `Main Queue`와 `Global Queue`를 기본적으로 제공한다.
    - `Main Queue`는 Serial Queue로 Main Thread에서 실행된다. 주로 UI 작업을 수행한다.
    - `Global Queue`는 Concurrent Queue로 여러 작업을 동시에 실행할 수 있다. Global Queue는 QoS에 따라 우선 순위를 가질 수 있다.
- Queue에 작업을 추가하는 방식은 `Asynchronous`, `Synchronous` 방식이 있다.
    - `Synchronous`(동기): 현재 실행 중인 Thread를 막고(**`Blocking`**), 해당 작업이 완료될 때까지 다음 작업을 실행하지 않는다.
    - `Asynchronous`(비동기): 현재 실행 중인 Thread를 막지 않고 작업을 Queue에 추가한다. 작업은 바로 실행되거나 대기열에 따라 나중에 실행된다.

ex)

1. `Serial Queue`에 `sync` 방식으로 작업을 추가

```swift
print("\nSerial Queue - sync")
serialQueue.sync {
    print("작업 1 시작")
    sleep(2)
    print("작업 1 완료")
}

serialQueue.sync {
    print("작업 2 시작")
    sleep(2)
    print("작업 2 완료")
}
print("Sync 작업 추가 후")
```

```
Serial Queue - sync
작업 1 시작
작업 1 완료
작업 2 시작
작업 2 완료
Sync 작업 추가 후
```

- 코드가 시작되면, 현재 Thread에서 첫번째 sync 실행
- Queue는 현재 Thread를 Blocking해, Thread는 작업이 완료될 때까지 다음 작업을 진행하지 못한다.
- 첫번째 작업이 끝난 후, 같은 Thread에서 두 번째 queue.sync 블록을 실행한다.
- 두 번째 작업이 완료되면 마지막 print 구문도 같은 Thread에서 실행된다.

1. `Serial Queue`에 `async` 방식으로 작업을 추가

```swift
let serialQueue = DispatchQueue(label: "serial")

print("Serial Queue - async")
serialQueue.async {
    print("작업 1 시작")
    sleep(2)
    print("작업 1 완료")
}

serialQueue.async {
    print("작업 2 시작")
    sleep(2)
    print("작업 2 완료")
}
print("Async 작업 추가 후")
```

```
Serial Queue - async
작업 1 시작
Async 작업 추가 후
작업 1 완료
작업 2 시작
작업 2 완료
```

- 마찬가지로 Serial Queue이기 때문에 작업은 순서대로 진행된다. 하지만, 마지막 print 구문은 바로 출력된다. Thread가 Blocking 당하지 않았기 때문이다.

1. Concurrent Queue에 async 방식으로 작업을 추가

```swift
let concurrentQueue = DispatchQueue(label: "concurrent", attributes: .concurrent)

print("Concurrent Queue - async")
concurrentQueue.async {
    print("작업 1 시작")
    sleep(2)
    print("작업 1 완료")
}

concurrentQueue.async {
    print("작업 2 시작")
    sleep(2)
    print("작업 2 완료")
}
print("Async 작업 추가 후")
```

```
Concurrent Queue - async
작업 1 시작
Async 작업 추가 후
작업 2 시작
작업 1 완료
작업 2 완료
```

- 병렬로 처리된다.

### GCD 동작 방식

- 작업이 Queue에 추가되면 GCD는 작업을 Thread Pool에서 적절한 Thread를 찾아 할당해 처리한다.
- Thread Pool은 여러 Thread를 관리하며, 작업 수에 따라 필요할 때 새로운 Thread를 추가하거나 기존 Thread를 재사용 하여 실행한다.
    - Concurrent Queue의 경우 여러 작업이 동시에 실행 될 수 있도록 Thread Pool에서 여러 Thread에 작업을 할당한다.
    - Serail Queue의 경우에는 하나의 Thread만 할당해 준다.

---

## Task와 GCD의 차이점

- Task는 작업 실행 스케줄을 시스템이 직접 제어한다. 각 작업은 필요한 지점에서 일시 중단(suspend)되거나 재개(resume)될 수 있다.
- 실제 Thread가 아닌 Task 단위로 스케줄링 되므로, Swift 런타임에 현재 실행 중인 작업이 일시 중단될 수 있는 시점을 효율적으로 관리해 다른 Task로 Context Switching을 수행한다.
- Thread Pool을 사용하지 않고 Thread 수를 최적화해 성능을 높이고, 작업 간의 Context Switching 비용을 줄인다.

- GCD는 작업이 큐에 쌓이면 Thread를 할당해 실행하지만, Context Switcing이 자주 발생할 수 있다.
- Task는 협력적 스레딩 방식을 통해 Thread의 자원을 효율적으로 사용하며, *Suspension point 에서만 필요한 Context Switching을 수행해 성능을 최적화 한다.*

ex)

1. 

```swift
let concurrentQueue = DispatchQueue(label: "concurrentQueue", attributes: .concurrent)

print("GCD 시작")

concurrentQueue.async {
    print("GCD 작업 1 시작")
    sleep(2)
    print("GCD 작업 1 완료")
}

concurrentQueue.async {
    print("GCD 작업 2 시작")
    sleep(2)
    print("GCD 작업 2 완료")
}

print("GCD 끝")
```

```
GCD 시작
GCD 끝
GCD 작업 1 시작
GCD 작업 2 시작
GCD 작업 1 완료
GCD 작업 2 완료
```

위의 코드에서 작업 1과 작업2는 각각 다른 스레드에서 동작, 각 작업이 진행되는 동안 스레드 풀을 통해 context switching이 일어날 수 있다.

2.

```swift
import Foundation

print("Task 시작")

Task {
    print("Task 작업 1 시작")
    try await Task.sleep(for: .seconds(2))
    print("Task 작업 1 완료")
}

Task {
    print("Task 작업 2 시작")
    try await Task.sleep(for: .seconds(2))
    print("Task 작업 2 완료")
}

print("Task 끝")

```

```
Task 시작
Task 끝
Task 작업 1 시작
Task 작업 2 시작
Task 작업 2 완료
Task 작업 1 완료
```

await Task.sleep을 실행하면 현재 작업이 **중단(suspend)**된다. 

다른 Task가 스레드를 사용할 수 있는 상태가 되는 것. 

(sleep은 단순히 대기하는 것 뿐이라 스레드 전환이 이루어 지지 않는다. 스레드 전환이 필요할 때만 Context Switching이 발생)

3.

```swift
Task {
    print("Task 작업 1 시작")
    for i in 1...3 {
        print("Task 작업 1 - 반복 \(i)")
        try await Task.sleep(for: .seconds(2))
    }
    print("Task 작업 1 완료")
}

Task {
    print("Task 작업 2 시작")
    for i in 1...3 {
        print("Task 작업 2 - 반복 \(i)")
        try await Task.sleep(for: .seconds(2))
    }
    print("Task 작업 2 완료")
}
```

```swift
Task 작업 1 시작
Task 작업 1 - 반복 1
Task 작업 2 시작
Task 작업 2 - 반복 1
Task 작업 2 - 반복 2
Task 작업 1 - 반복 2
Task 작업 2 - 반복 3
Task 작업 1 - 반복 3
Task 작업 2 완료
Task 작업 1 완료
```

위의 코드에서 작업 2가 연속으로 실행되었다. await가 있는데 왜 연속으로 실행 되는거임 번갈아서 출력되야 하는거 아님? 

await를 만나면 무조건 suspend 상태로 진입한다. 그리고 await에서 깨어난 후 문맥 전환이 즉시 발생하지 않을 수도 있다. 시스템이 현재 Task가 더 빠르게 진행될 수 있다고 판단하면 같은 Task가 연속으로 실행되도록 한다. (스케줄링 최적화)

1.	**일시 중단 지점에서만 전환(suspension points)**:

•	**Task** 방식은 **일시 중단 지점에서만 문맥 전환**이 발생합니다. Swift의 async/await는 협력적으로 비동기 작업을 관리하여, 코드가 await 키워드를 만날 때 **현재 스레드를 반납**하고 다른 Task를 실행할 수 있도록 합니다. 이는 비동기 작업의 지점을 명확히 정의하기 때문에, **문맥 전환이 필요한 지점을 Swift 런타임이 최적화**할 수 있습니다.

•	반면, **GCD**는 스레드 풀을 통해 작업을 할당하며, 비동기 작업을 동시 처리하는 과정에서 **작업 전환 시점이 명확하지 않아 불필요한 문맥 전환이 더 자주 발생**할 수 있습니다.

2.	**스레드 풀과 스레드 수 관리**:

•	**GCD**는 **스레드 풀을 통해 작업을 관리**하며, 동시성 수준을 조절합니다. 하지만 작업이 많아지면 스레드 풀은 새로운 스레드를 추가하고, 작업이 끝난 스레드를 반환하는 과정에서 스레드 생성과 소멸이 빈번하게 일어날 수 있습니다. 이 과정에서 **스레드 수가 증가하며 문맥 전환 오버헤드가 커질 가능성**이 있습니다.

•	**Task** 방식에서는 **스레드 풀을 사용하지 않고, 적은 스레드 수로 협력적 방식으로 작업을 관리**합니다. 필요할 때만 일시 중단 지점에서 문맥 전환이 일어나므로, 과도한 스레드 증가와 불필요한 문맥 전환을 줄여줍니다.

3.	**스케줄링 효율성**:

•	**Task 방식은 최적화된 스케줄링을 통해 작업을 관리**합니다. 각 Task는 Swift의 async/await 시스템에 의해 최적으로 스케줄링되므로, 시스템은 우선순위나 가용 리소스에 따라 작업의 실행 여부를 정교하게 조정할 수 있습니다.

•	**GCD**는 작업이 큐에 쌓이면 즉시 스레드를 할당하려고 하기 때문에, 많은 작업이 쌓일 경우 스레드가 불필요하게 많이 생성되고, 스레드 간 전환 비용이 증가할 수 있습니다.

4.	**더 적은 오버헤드**:

•	GCD의 스레드 풀 방식은 작업이 많아질수록 문맥 전환과 스레드 전환 오버헤드가 증가하며, 메모리와 CPU를 더 많이 소비할 수 있습니다.

•	Task는 비동기 작업의 일시 중단 지점에서만 전환을 하므로, 스레드 수가 적은 상태에서도 동시성을 효율적으로 유지할 수 있어 **경량화된 오버헤드로 성능이 최적화**됩니다.

> 문맥 전환이 일어나면 왜 성능이 안좋아여?
> 
- 현재 작업의 상태를 저장하고 새로 전환될 작업의 상태를 로드하는데 메모리 소비
- Context Switching이 발생하면 이전 작업의 캐시 데이터가 손실된다.

---

Task 클로저에서는 현재 컨텍스트를 자동으로 캡처해 self로 명시적 캡처할 필요가 없다.
