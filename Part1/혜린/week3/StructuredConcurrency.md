# Week2 복기
Task.yield 내부에서 continuation을 생성하고 있나 ?!

```swift
public static func yield() async {
    return await Builtin.**withUnsafeContinuation** { (continuation: Builtin.RawUnsafeContinuation) -> Void in
      let job = _taskCreateNullaryContinuationJob(
          priority: Int(Task.currentPriority.rawValue),
          continuation: continuation)
      _enqueueJobGlobal(job)
    }
  }
```

URLSession.shared.data(from url)도…

```swift
    public func data(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse) {
        let cancelState = CancelState()
        return try await withTaskCancellationHandler {
            try await **withCheckedThrowingContinuation** { continuation in
                let completionHandler: URLSession._TaskRegistry.DataTaskCompletion = { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (data!, response!))
                    }
                }
                let task = dataTask(with: _Request(url), behaviour: .dataCompletionHandlerWithTaskDelegate(completionHandler, delegate))
                task._callCompletionHandlerInline = true
                task.resume()
                cancelState.activate(task: task)
            }
        } onCancel: {
            cancelState.cancel()
        }
    }
```
결론... 메서드 내부적으로 continuation을 생성하고 있기 때문에 instrument로 봤을 때 continuation이 생성되는게 맞았다 !! 굿

# WWDC
[WWDC 2021 - Explore structured concurrency in Swift](https://ccoli.notion.site/Explore-structured-concurrency-in-Swift-144aba3750d780308a4fef8da76b311a?pvs=4)

# Task priority
> Task group을 사용할 때 어떻게 우선순위를 전파하고 이것이 우선순위 역전을 피하는데 도움이 되는지 알아보자
> 
- 우선순위 역전이란?
    - 우선순위가 높은 task가 우선순위가 낮은 작업의 결과를 기다릴 때 발생하는 현상
- high proiority task가 생성되면 이에 따라 자식 task의 우선순위도 high로 변경 → 그래야 자식 task의 priority가 medium이라서 밀리고 → 이에 따라 high priority인 parent task가 기다리지 않기 때문에 = 우선순위 역전을 피할 수 있어서
- 모든 자식 task들의 우선순위가 올라가는건 어떤 작업이 다음으로 완료될 가능성이 가장 높은지 알 수 없기 때문에
- cocurrency 런타임은 작업 스케줄을 잡을 때 priority queue(우선순위 큐)를 사용함
- 한 번 우선순위를 올리면 task의 수명 내내 변경됨 (다시 되돌릴 수 없음)

# Async-let
## 왜 async-var는 안될까?
```swift
func fetchUsername() async -> String {
    // complex networking here
    "Taylor Swift"
}

async var username = fetchUsername()
username = "Justin Bieber"
print("Username is \(username)")
```
비동기 코드의 이해가 엄청나게 복잡해지고 값의 데이터 흐름에 대한 가정을 어렵게 만들어 잠재적인 최적화를 저해할 수 있기 때문에 let으로 한정