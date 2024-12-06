# addTask vs addTaskUnlessCancelled

### 1. addTask

> addTask에서 취소는 아래와 같은 특징을 가질 것이다.
> 
- 작업이 취소된 상태여도 일단 태스크를 추가한다.
- 취소 상태를 직접 체크해야 한다. (Task.isCancelled 또는 try Task.checkCancellation())
- **작업 취소 후에도 이미 추가된 태스크는 실행될 수 있다.**

### 2. addTaskUnlessCancelled

- 작업 추가 시점에 이미 취소 상태면 태스크를 아예 추가하지 않음
- 반환값으로 작업 추가 성공 여부를 바로 알 수 있음
- 더 빠른 취소 처리 가능

```swift
func testCancellation() async {
    do {
        try await withThrowingTaskGroup(of: Void.self) { group -> Void in
            group.addTaskUnlessCancelled {
                print("추가")
                try await Task.sleep(nanoseconds: 1_000_000_000)
                throw ExampleError.badURL
            }
            group.addTaskUnlessCancelled {
                print("추가")
                try await Task.sleep(nanoseconds: 2_000_000_000)
                print("Task is cancelled: \(Task.isCancelled)")
            }

            group.addTaskUnlessCancelled {
                print("추가")
                try await Task.sleep(nanoseconds: 5_000_000_000)
                print("Task is cancelled: \(Task.isCancelled)")
            }
            group.cancelAll()
            try await group.next()

        }
    } catch {
        print("Error thrown: \(error.localizedDescription)")
    }
}
```

1. `group.addTaskUnlessCancelled`를 사용하여 3개의 비동기 작업을 그룹에 추가한다.
2. 각 작업은 다른 시간 동안 `Task.sleep`을 사용하여 일시 중단된다.
3. 첫 번째 작업은 1초 후에 `ExampleError.badURL`을 던진다.
4. 두 번째와 세 번째 작업은 각각 2초와 5초 동안 일시 중단된 후 `Task.isCancelled`의 값을 출력한다.
5. `group.cancelAll()`을 호출하여 그룹의 모든 작업을 취소한다.
6. `try await group.next()`를 호출하여 그룹에서 다음 완료된 작업의 결과를 기다린다. 이 경우 첫 번째 작업이 오류를 던지므로 `catch` 블록으로 이동한다.

> `addTaskUnlessCancelled`와 `addTask`의 주요 차이점은 그룹이 이미 취소된 경우 `addTaskUnlessCancelled`는 새 작업을 추가하지 않는다는 것이다.

반면에 `addTask`는 그룹이 취소되었는지 여부에 관계없이 항상 새 작업을 추가한다.
> 

- 해당 코드에서는 group.cancelAll()을 호출하기 전에 작업을 추가하므로 addTaskUnlessCancelled를 사용하더라도 모든 작업이 그룹에 추가된다.
- `addTaskUnlessCancelled`를 사용하더라도 `group.cancelAll()`이 호출되기 전에 모든 작업이 추가되므로 `addTask`를 사용하는 것과 동일한 동작을 한다.

```swift
func a() async {
    await withTaskGroup(of: Void.self) { group in
        for await i in tickSequence() {
            group.addTask(operation: { await self.b() })

            if i == 3 {
                group.cancelAll()
            }
        }
    }
}

func b() async {
    let start = CACurrentMediaTime()
    while CACurrentMediaTime() - start < 3 { }
}

func tickSequence() -> AsyncStream<Int> {
    AsyncStream { continuation in
        Task {
            for i in 0 ..< 12 {
                try await Task.sleep(nanoseconds: NSEC_PER_SEC / 2)

                continuation.yield(i)
            }
            continuation.finish()
        }
    }
}
```

- 비동기 작업을 그룹화하고 취소하는 방법을 보여주는 예시
1. `tickSequence()` 함수는 `AsyncStream`을 반환한다
    - 이 스트림은 0부터 11까지의 정수를 0.5초 간격으로 생성한다.
2. `a()` 함수는 `withTaskGroup`을 사용하여 비동기 작업 그룹을 생성한다.
3. `for await` 루프를 사용하여 `tickSequence()`에서 생성된 각 정수에 대해 반복한다.
4. 각 반복에서 `group.addTask`를 호출하여 새로운 작업을 그룹에 추가한다
    - 이 작업은 `b()` 함수를 호출한다.
5. 정수가 3이 되면 `group.cancelAll()`을 호출하여 그룹의 모든 작업을 취소한다.
6. `b()` 함수는 현재 시간을 기록하고, 3초가 경과할 때까지 빈 루프를 실행한다.

> 이 코드의 문제점은 `b()` 함수가 취소에 응답하지 않는 것이다.

그룹이 취소된 후에도 `b()` 함수는 계속 실행된다. 
(b함수 내부에서 작업 취소 여부를 확인하지 않기 때문에)

또한, `a()` 함수는 그룹이 취소된 후에도 `tickSequence()`에서 생성된 모든 정수에 대해 계속 작업을 추가하려고 한다.
(`group.addTask`를 호출하여 새 작업을 추가하고, 이 과정에서 그룹이 취소되었는지 여부를 확인하지 않음)
> 

이러한 문제를 해결하려면

1. `b()` 함수에서 `Task.isCancelled`를 확인하여 작업이 취소되면 즉시 반환하도록 해야 한다.
2. `a()` 함수에서 `group.addTaskUnlessCancelled`를 사용하여 그룹이 취소된 경우 새 작업을 추가하지 않도록 해야 한다.
3. 또한, `addTaskUnlessCancelled`의 반환값을 확인하여 그룹이 취소되면 루프를 종료해야 한다.

```swift
func a() async {
    await withTaskGroup(of: Void.self) { group in
        for await i in tickSequence() {
            guard group.addTaskUnlessCancelled(operation: { await self.b() })
            else { break }

            if i == 3 {
                group.cancelAll()
            }
        }
    }
}

func b() async {
    let start = CACurrentMediaTime()
    while CACurrentMediaTime() - start < 3 {
        if Task.isCancelled { return }
    }
}

func tickSequence() -> AsyncStream<Int> {
    AsyncStream { continuation in
        Task {
            for i in 0 ..< 12 {
                try await Task.sleep(nanoseconds: NSEC_PER_SEC / 2)
                
                continuation.yield(i)
            }
            continuation.finish()
        }
    }
}
```

- `a()` 함수에서 `group.addTask` 대신 `group.addTaskUnlessCancelled`를 사용한다.
- `addTaskUnlessCancelled`의 반환값을 `guard` 문과 함께 사용하여, 그룹이 취소되면 루프를 종료한다.
- `b()` 함수에서 `Task.isCancelled`를 확인하여 작업이 취소되면 즉시 반환한다.
    - 이렇게 하면 그룹이 취소된 후에 `b()` 함수가 계속 실행되는 것을 방지할 수 있다.

`addTask`의 동작:

- `addTask`는 그룹의 취소 여부와 관계없이 항상 새 작업을 그룹에 추가한다.
- 그룹이 이미 취소된 상태에서 `addTask`를 호출하면, 취소된 그룹에 새 작업이 추가된다.
- 이는 불필요한 작업 생성과 리소스 낭비를 초래할 수 있다.

`addTaskUnlessCancelled`의 동작:

- `addTaskUnlessCancelled`는 그룹의 취소 여부를 확인한 후에 작업을 추가한다.
- 그룹이 아직 취소되지 않은 상태라면, 작업을 추가하고 `true`를 반환한다.
- 그룹이 이미 취소된 상태라면, 작업을 추가하지 않고 `false`를 반환한다.
- 이를 통해 불필요한 작업 생성을 방지할 수 있다.

- 작업 추가 중에 그룹이 취소될 가능성이 있다면, `addTaskUnlessCancelled`를 사용하는 것이 좋다.
- `addTaskUnlessCancelled`는 그룹 취소 여부를 확인하고, 불필요한 작업 생성을 방지할 수 있다.
