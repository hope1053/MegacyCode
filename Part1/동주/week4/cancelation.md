# 12월 6일 (금)

# GCD Cancelation

GCD에서 작업 큐에 추가된 작업은 예약되면 실행 취소가 불가능하다. 애초에 GCD 자체적으로 취소하는 API를 제공하지 않는다.

때문에 작업 취소를 구현하려면 isCancelled 플래그나 GCD 작업을 커스텀 Operation으로 매핑해 구현해야 한다.

## 플래그 기반 취소

```swift
class GCDTaskManager {
    private var isCancelled = false

    func startLongRunningTask() {
        let queue = DispatchQueue.global(qos: .background)

        queue.async {
            for i in 1...10 {
                if self.isCancelled {
                    print("작업이 취소되었습니다.")
                    return
                }
                print("작업 중: \(i)")
                Thread.sleep(forTimeInterval: 1) // 작업 시뮬레이션
            }
            print("작업 완료")
        }
    }

    func cancelTask() {
        isCancelled = true
    }
}

// 실행 예제
let taskManager = GCDTaskManager()
taskManager.startLongRunningTask()

DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
    taskManager.cancelTask()
    print("취소 요청됨")
}

```

```
작업 중: 1
작업 중: 2
작업 중: 3
취소 요청됨
작업이 취소되었습니다.
```

## (참고) OperationQueue

여러 `Operation`객체를 관리하고, 작업의 실행 순서, 우선순위, 의존성 등을 조정할 수 있는 객체. `GCD`를 기반으로 동작하며, 여러 작업을 효율적으로 실행하고 조율한다.

### 특징

- **우선 순위(Priority), 준비 상태, 의존성**에 따라 `Queue`에서 대기 중인 작업을 실행시킨다.
- Queue에 담긴 Operation 객체는 작업이 완료될 때까지 Queue에 남아 있는다.
- Queue에서 Operation들을 삭제하거나 실행시킬 수 있다.

### Operation 상태

- `Pending`: Queue에 Operation(task)가 추가 될 경우
- `Ready`: pending에서 모든 조건 만족 시 해당 상태로 변경
- `Executing`: start() 메소드를 호출해 작업이 시작된 경우
- `Finished`: 작업이 완료된 경우 해당 상태로 변경되고 Queue에서 Operation이 제거
- `Cancelled`: pending, ready, executing에서만 변경 가능하고, cancelled상태가 되었다가 바로 finish상태로 변경

### 실행 순서 결정

- OperationQueue는 Queue에 추가된 Operation(작업)을 우선순위(Priority), 준비 상태(isReady), 의존성에 따라 실행한다.
- 작업의 준비 상태(isReady)가 true가 되면, Queue는 해당 작업을 실행 대기열로 이동시킨다.
- 만약 우선순위가 같고 모두 isReady라면 FIFO 규칙을 따라 실행한다.

### e.g.) 간단한 Operation

```swift
let operation1 = BlockOperation {
    print("작업 1 실행")
}

let operation2 = BlockOperation {
    print("작업 2 실행")
}

// 작업 2는 작업 1이 완료된 이후 실행
operation2.addDependency(operation1)

let queue = OperationQueue()
queue.addOperations([operation1, operation2], waitUntilFinished: true)
```

# GCD(Operation) Cancelation

작업이 취소되면 작업의 취소 상태를 isCancelled로 하고, 직접 종료해야 한다. 대기 중인 작업은 실행되지 않는다. 취소된 작업은 의존성을 무시하고 즉시 start() 메서드를 호출해 작업을 종료 상태로 전환한다.

→ `isCancelled`를 통해 작업 취소를 관리한다.

- 기존 GCD 작업을 Operation으로 래핑 후 취소 상태를 부여할 수 있다.
<img width="399" alt="%E1%84%89%E1%85%B3%E1%84%8F%E1%85%B3%E1%84%85%E1%85%B5%E1%86%AB%E1%84%89%E1%85%A3%E1%86%BA_2024-12-06_12 56 05" src="https://github.com/user-attachments/assets/4e28fa89-9c5c-4a47-9f13-e6d7d7d5d672">

### e.g.) Custom Operation을 사용해 Cancel 시 전처리 작업 가능

```swift
class GCDOperation: Operation {
    private let task: () -> Void

    init(task: @escaping () -> Void) {
        self.task = task
    }

    override func main() {
        if isCancelled {
            print("작업이 취소되었습니다.")
            return
        }

        task()
    }
}

// OperationQueue 생성
let queue = OperationQueue()

// GCD 작업을 캡슐화
let operation1 = GCDOperation {
    for i in 1...5 {
        if OperationQueue.current?.operations.first?.isCancelled == true {
            print("작업 1이 취소되었습니다.")
            return
        }
        print("작업 1 수행 중: \(i)")
        Thread.sleep(forTimeInterval: 0.5)
    }
    print("작업 1 완료")
}

queue.addOperation(operation1)

// 1초 후 작업 취소
DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
    operation1.cancel()
    print("모든 작업이 취소되었습니다.")
}
```

```swift
작업 1 수행 중: 1
작업 1 수행 중: 2
작업 1 수행 중: 3
모든 작업이 취소되었습니다.
작업 1이 취소되었습니다.
```

### e.g.) 네트워크 작업 취소

```swift
class NetworkOperation: Operation {
    private var task: URLSessionDataTask?

    override func main() {
        if isCancelled {
            print("작업이 취소되었습니다.")
            return
        }

        let url = URL(string: "https://dongjoo.com")!
        let session = URLSession.shared

        task = session.dataTask(with: url) { data, response, error in
            if self.isCancelled {
                print("네트워크 작업이 취소되었습니다.")
                return
            }
            print("데이터 수신 완료")
        }

        task?.resume()

        // 대기 (네트워크 작업 종료 시까지)
        while !isFinished {
            if isCancelled {
                task?.cancel()
                print("작업 도중 취소되었습니다.")
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    override func cancel() {
        super.cancel()
        task?.cancel()
    }
}

let queue = OperationQueue()
let networkOperation = NetworkOperation()
queue.addOperation(networkOperation)

// 2초 후 작업 취소
DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
    networkOperation.cancel()
    print("네트워크 작업 취소 요청됨")
}
```

# Task Cancelation

## 협력적 취소 (Cooperative Cancellation)

협력적 취소는 Task가 취소되었음을 알려는 신호(State)를 보내고, Task 내에서 직접 취소를 처리하는 모델이다.

→ 취소 상태를 확인하고 작업 중단 여부와, 중단 방식은 무엇인지 Task가 직접 결정해야 한다.

### Task 취소 과정

1. 취소 신호 전송
    - Task.cancel() 메서드를 호출해 Task에 취소 신호 전송
    - Task의 isCancelled 값이 true로 변경
    
2. 취소 상태 확인 
    - 작업 내에서 Task.isCancelled 또는 Task.checkCancellation()을 호출해 취소 상태를 확인
    
3. 취소 후 처리
    - 작업이 취소되었을 때, 명시적으로 작업을 종료하거나 리소스를 정리해야 한다.

### 장점

1. 유연성 제공
    - 작업의 성격에 따라 작업의 중단 시점과 방법을 결정할 수 있다.
    
2. 안정성과 예측 가능성
    - 강제 취소 모델은 작업이 즉시 취소되기 때문에 공유 리소스 상태가 손상되거나, 메모리 누수가 발생하는 등 예상치 못한 동작이 발생할 수 있다.
    
3. 구조적 동시성과의 통합
    - 부모 작업이 취소되면 자식 작업도 취소 신호를 받는다.
    
    ```swift
    func parentTask() async {
        let childTask = Task {
            for i in 1...5 {
                try Task.checkCancellation()
                print("작업 수행 중: \(i)")
                try await Task.sleep(for: .seconds(1))
            }
        }
    
        // 2초 후 부모 작업 취소
        Task {
            try await Task.sleep(for: .seconds(2))
            childTask.cancel()
            print("자식 작업이 취소되었습니다.")
        }
    
        try? await childTask.value
    }
    
    Task {
        await parentTask()
    }
    ```
    
    ```
    작업 수행 중: 1
    작업 수행 중: 2
    자식 작업이 취소되었습니다.
    ```
    

1. 선택적 취소
    
    ```swift
    func selectiveCancellationTask() async {
        let parentTask = Task {
            let childTask1 = Task {
                for i in 1...5 {
                    try Task.checkCancellation()
                    print("작업 1 진행 중: \(i)")
                    try await Task.sleep(for: .seconds(1))
                }
            }
    
            let childTask2 = Task {
                for i in 1...5 {
                    print("작업 2 진행 중: \(i)")
                    try await Task.sleep(for: .seconds(1))
                }
            }
    
            // 2초 후 작업 1만 취소
            try await Task.sleep(for: .seconds(2))
            childTask1.cancel()
            print("작업 1 취소됨")
            try await childTask1.value
            try await childTask2.value
        }
    
        try? await parentTask.value
    }
    Task {
        await selectiveCancellationTask()
    }
    ```
    
    ```
    작업 1 진행 중: 1
    작업 2 진행 중: 1
    작업 1 진행 중: 2
    작업 2 진행 중: 2
    작업 2 진행 중: 3
    작업 1 취소됨
    작업 2 진행 중: 4
    작업 2 진행 중: 5
    ```
