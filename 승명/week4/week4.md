# Swift Concurrency 4주차

## 작업의 취소
1. 작업 내부의 비동기 함수들에 취소를 전파
    - 내부의 Task와 Task.detached 까지 취소를 전파하는 것은 아니다.
    - 부모 작업은 async let / TaskGroup 과 같은 자식 작업에 취소를 전파한다.
2. 취소를 전파, Task.isCancelled 속성 true로 설정한다. 실제로 작업을 중간에 즉시 멈추게 하는 개념이 아니다. 중간에 return 되어 작업 자체를 끝내는 개념이 아니다.
    - 작업을 취소가기 위해선 취소 에러를 던지고 이를 처리하는 개발자의 구현이 필요하다. 결국 항상 취소를 고려해서 비동기 동작을 설계가 필요하다.

```Swift
func asyncTest(id: Int) async throws {
    print("작업 시작 - id:", id)

    guard !Task.isCancelled else {
        return
    }
    sleep(4)
    
    print("작업 종료 - id:", id)
}

let task = Task {
    try await asyncTest(id: 1)
    try await asyncTest(id: 2)
    try await asyncTest(id: 3)
    
    Task {
        try await asyncTest(id: 4)
        try await asyncTest(id: 5)
    }
}

sleep(2)
task.cancel()

// 실행결과 -> 작업번호 4,5는 별도의 작업이라 취소되지 않음
// 2,3만 작업이 종료된 것을 확인할 수 있다.
작업 시작 - id: 1
작업 종료 - id: 1
작업 시작 - id: 2
종료된 작업 - id: 2
작업 시작 - id: 3
종료된 작업 - id: 3
작업 시작 - id: 4
작업 종료 - id: 4
작업 시작 - id: 5
작업 종료 - id: 5
```

## 작업 취소의 처리방법

- Task.isCancelled 확인 후 처리

```Swift
// 함수만 바로 종료할 때
if Task.isCancelled {
    return 
}

// 상위 Task에게 에러를 전달해 상위 Task까지 종료할 때
if Task.isCancelled {
    throw CancellationError( ) 
}
```

- Task.checkCancellation() 사용

```Swift
// 메서드를 실행하면 취소를 확인하고 취소 되었다면 내부에서 CancellationError() 에러를 던진다.
try Task.checkCancellation()

// checkCancellation의 내부 코드
public static func checkCancellation() throws {
    // Task.isCancelled가 true 면
    if Task<Never, Never>.isCancelled {
        // CancellationError()를 던지는 것을 확인 가능
        throw _Concurrency.CancellationError()
    }
}
```

- URLSession에서의 취소 처리

```Swift
// URLSession에서 취소가 되면 URLError.Code.cancelled를 던저준다. 
try await URLSession.shared.data(from: url) 
```

## SwiftUI View의 task modifier
- SwiftUI의 onAppear는 동기 함수라 따로 Task 생성해야 한다.
    - task로 간단하게 작성 가능, task는 View와 생명주기가 같아서 view가 살아지면 task안에 작업도 자동 취소된다.

```Swift
.onAppear {
    Task {
        try await fetchImage()
    }
}

.task {
    try await fetchImage()
}
```

![Dec-05-2024 16-29-33](https://github.com/user-attachments/assets/9c229070-0677-4b81-9895-9913b6a779a2)

```Swift
// id 값을 설정하고 id 값이 변경되면 SwiftUI는 자동으로 이전의 작업을 취소하고 새로운 값으로 새 작업을 생성합니다.
Text(status ?? "Signed Out")
    .task(id: server) {
        let sequence = NotificationCenter.default.notifications(
            named: .didUpdateStatus,
            object: server
        ).compactMap {
            $0.userInfo?["status"] as? String
        }
        for await value in sequence {
            status = value
        }
    }
    
.task(id: flag) {
    do {
        print("작업 시작: \(flag)")
        try await Task.sleep(for: .seconds(3))
        flag += 1
    } catch {
        print(error.localizedDescription)
    }
}

// 실행 결과
작업 시작: 0
작업 시작: 1
작업 시작: 2
작업 시작: 3
작업 시작: 4
작업 시작: 5
    ...
```

## 취소 핸들러
- withTaskCancellationHandler(operation:onCancel:) 
    - operation은 비동기 함수, onCancel은 동기 함수, 취소가 일어나고 즉각적으로 실행

```Swift
let result = try await withTaskCancellationHandler {
    // 에러를 던지는 비동기 함수 호출
} onCancel: {
    // 취소시 실행할 작업
    print("작업 취소")
}

// withTaskCancellationHandler의 내부 코드
public func withTaskCancellationHandler<T>(
  operation: () async throws -> T,
  onCancel handler: @Sendable () -> Void,
  isolation: isolated (any Actor)? = #isolation
) async rethrows -> T {
  // 작업에 취소 기록을 무조건 추가
  // 작업이 이미 취소된 경우 즉시 실행
  let record = _taskAddCancellationHandler(handler: handler)
  defer { _taskRemoveCancellationHandler(record: record) }

  return try await operation()
}
```
