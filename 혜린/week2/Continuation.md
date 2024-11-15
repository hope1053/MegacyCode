# Continuation의 생명 주기
## 생성
> async 함수에서 await 지점 만날 때, Task가 suspend 될 때

하지만 await 지점을 만났다고 무조건 continuation이 생기는건 아니고 내부 작업에 따라 다름
- 네트워크 요청과 같은 비동기 작업, Task sleep, Task yield, 다른 actor context로 전환이 필요한 경우 등에만 continuation이 생성되고
```swift
// continuation이 생성됨
// 일케 Task 내부에 sleep이 있거나 비동기 작업이거나 이런 경우에는 continuation 생성
let result = await Task.detached {
    var sum = 0
    for i in 0...10_000_000 { sum += i }  // 시간이 좀 더 걸리는 작업
    try? await Task.sleep(nanoseconds: 1_000_000_000)  // 강제로 지연
    return sum
}.value
```
- 내부 작업이 동기작업인 경우에는 continuation이 안생김. 왜냐면 Task가 생성되자마자 끝나서 Task를 suspend할 일이 없기 때문에
```swift
  @objc private func task1ButtonTapped() {
    Task {
      let result = await basicAsyncTask()
      statusLabel.text = ":white_check_mark: \(result)"
    }
  }

  private func basicAsyncTask() async -> String {
    // Detached Task가 value를 요청하기 전에 내부 작업이 완료되는 상황
    // 내부 작업이 동기 작업으로 이루어져있기 때문에 해당 Task를 실행할 때는 continuation이 생성되지 않음 (Swift 내부적으로 최적화를 시키기 위한 전략)
    let result = await Task.detached(priority: .userInitiated) {
      var sum = 0
      for i in 0...100_000 { sum += i }
      return sum
    }.value
     
    try? await Task.sleep(nanoseconds: 1_000_000_000)
     
    return "Basic Task Completed"
  }
```
## 소멸
> Task가 resume되어 작업 완료될 때, 에러 발생했을 때, Task가 취소됐을 때

Continuation은 resume 호출 시점에 소멸되는 것이 아니라, resume된 후 **실제로 해당 비동기 컨텍스트로 제어가 돌아와서 작업이 완료될 때** 소멸됨
```swift
func someAsyncWork() async {
    await withCheckedContinuation { continuation in
        someAsyncAPI { result in
            continuation.resume(returning: result)
            // 여기서는 continuation이 아직 살아있음
            
            doSomething()  // 이 코드도 실행됨
        }
    }
    // 이 지점에서 continuation이 소멸됨
}
```
```swift
func problematicPattern() async {
    await withCheckedContinuation { continuation in
        someAsyncAPI { result in
            continuation.resume(returning: result)
            
            // 위험! continuation이 아직 소멸되지 않았으므로 
            // resume을 다시 호출할 수 있음
            if someCondition {
                continuation.resume(returning: anotherResult)  // 크래시 발생!
            }
        }
    }
}
```
## 주의해야할 점
> Continuation은 resume 호출 직후에 정리하면 안됨
> defer 사용 혹은 작업이 완료된 후에 정리해야함

```swift
class AsyncOperationManager {
    private var continuationStorage: CheckedContinuation<String, Error>?
    
    // 잘못된 예시
    func badExample() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuationStorage = continuation
            
            someAsyncWork { result in
                self.continuationStorage?.resume(returning: result)
                self.continuationStorage = nil  // 위험! 너무 일찍 정리하려고 함
            }
        }
    }
    
    // 올바른 예시
    func goodExample() async throws -> String {
        defer {
            // 비동기 작업이 완전히 완료된 후 정리
            self.continuationStorage = nil
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuationStorage = continuation
            
            someAsyncWork { result in
                self.continuationStorage?.resume(returning: result)
                // 여기서 정리하지 않음
            }
        }
    }

    func anotherSafeApproach() async throws -> Data {
        let result = try await withCheckedThrowingContinuation { ... }
        // 이 시점에서 정리
        cleanup()
        return result
    }
}
```
```swift
func example() async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        someAsyncWork { result in
            print("1")
            continuation.resume(returning: result)  // resume 호출
            print("2")  // 이 코드는 실행됨
            // 아직 비동기 컨텍스트가 전환되지 않은 상태
        }
    }
    print("3")  // 이제 비동기 컨텍스트가 전환된 상태
}
```
# Continuation에는 어떤 메타데이터가 저장되는가?
정확하게 확인할 수 있는 레퍼런스는 못찾음…ㅜㅜ 

실행 중이던 함수의 위치 정보, 로컬 변수들의 상태, 에러 처리 정보, Task 관련 메타데이터(TaskPriority, taskID), 실행 컨텍스트 정보 등이 Continuation에 포함돼있지 않을까 예상
# Continuation 동작 원리
- continuation은 **task가 suspend 되었을 때 발생**하며, resume 될 때 이를 이용해 suspension point로 돌아갈 수 있음
- 새로운 Swift 동시성 모델에서는 각 task에 대해서 스레드를 생성하는 대신 **continuation을 할당**합니다.
- 일반적으로 실행 중인 프로세스 내에서 모든 스레드는 독립적인 stack 영역과 **프로세스 내에서 공유되는 heap 영역**을 가지고 있음. 이때 stack은 함수 호출의 상태를 저장하기 위해 사용됨. 지역 변수와 반환 주소값 등 함수 호출에 필요한 정보들을 함께 저장하고 있음
- (기존에는 스레드를 바꿔가면서 관리하던 비동기 프로그래밍…) 그러나 Swift Concurrency에 도입된 코루틴에서는 비동기 함수의 실행을 stack과 heap에서 관리합함. **stack**에는 비동기 함수를 실행할 때 사용되지 않는 지역변수들을 저장함. 추가로 **heap**에는 suspension point에서 실행하는데 필요한 함수 컨텍스트들을 저장함. 이것을 **continuation**이라고 부르며, 이를 통해 일시정지된 함수의 상태를 추적해 어디서부터 재개할지 알 수 있음.
- continuation은 heap에 저장되기 때문에 스레드 간의 함수 컨텍스트를 공유할 수 있음.
- 먼저 미래에 사용될 가능성이 있는 변수들이 continuation의 형태로 heap에 저장됨. suspend 되었던 함수가 resume 되면, stack의 최상단 frame이 해당 함수 frame으로 교체됨. 이미 heap에 함수 컨텍스트가 저장되어 있기 때문에 새로운 stack frame을 생성하지 않고 교체만으로도 동작할 수 있음.
- 함수의 실행이 일시중지될 때, 해당 함수의 현재 실행 상태(지역 변수, 실행 위치등)를 힙(Heap)에 저장하게 되는데, Continuation이 (스택에서 실행중인) 콜 스택의 현재 상태를 캡처해서 (힙에 잠시 저장해놓고) 함수(작업)이 재개될때 작업이 중단된 지점부터 다시 실행을 계속할 수 있게 만들어 주는 원리
# Checked Continuation을 사용하는 이유
continuation이 resume되지 않아서 memory leak이 발생하는 경우에 대한 경고를 확인할 수 있기 때문에
```swift
func requestPreviewImage() async throws -> UIImage {
  let primaryImageProvider = self.linkMetadata?.imageProvider ?? self.linkMetadata?.iconProvider
  return try await withCheckedThrowingContinuation { continuation in
    primaryImageProvider?.loadObject(ofClass: UIImage.self) { (previewImage, error) in
      guard let previewImage = previewImage as? UIImage,
      error == nil
      else {
        continuation.resume(throwing: LinkMetadataServiceError.contentsCouldNotBeLoaded)
        return
      }
  
      continuation.resume(returning: previewImage)
    }

    // primaryImageProvider가 nil일 경우 오게되는 컨텍스트
  }
}
```
- Unless you are sure that performance is significantly improved by using UnsafeContinuation, it is advisable to use CheckedContinuation. [🔗](https://asynclearn.medium.com/mastering-continuations-in-swift-a-comprehensive-guide-454b41a40681)

- CheckedContinuation과 UnsafeContinuation은 동일한 인터페이스를 갖고 있다고 합니다~
Because both types have the same interface, you can replace one with the other in most circumstances, without making other changes. [🔗](https://developer.apple.com/documentation/swift/checkedcontinuation)

# Continuation은 왜 한 번만 재개될 수 있을까?
- 성능 최적화: Continuation은 성능 최적화를 위해 설계되었습니다. 한 번만 재개할 수 있도록 제한함으로써 불필요한 오버헤드를 피할 수 있습니다.

- 재개 상태 추적: Continuation은 재개 시점의 상태를 추적하고 관리해야 합니다. 여러 번 재개하면 상태 관리가 복잡해져 오류가 발생할 수 있습니다.

# Await MainActor.run {} vs Task '{@MainActor in}'
1. Task 생성 및 취소 관점
    
    ```swift
    // MainActor.run - 새로운 Task를 생성하지 않음
    await MainActor.run {
        // 기존 Task의 컨텍스트를 유지한 채로 메인 스레드로 전환
        updateUI()
    }
    
    // Task { @MainActor in } - 새로운 Task를 생성
    let task = Task { @MainActor in
        // 새로운 독립적인 Task가 생성됨
        updateUI()
    }
    // task.cancel() 가능
    ```
    
2. 부모 Task와의 관계
    
    ```swift
    Task {
        // 부모 Task
        try await someWork()
        
        await MainActor.run {
            // 부모 Task의 취소 상태를 그대로 상속
            // 부모가 취소되면 이 블록도 취소됨
            updateUI()
        }
        
        Task { @MainActor in
            // 새로운 독립적인 Task이므로
            // 부모 Task가 취소되어도 계속 실행될 수 있음
            updateUI()
        }
    }
    ```
    
3. 오버헤드와 성능
    
    ```swift
    class MyViewController: UIViewController {
        func example1() async {
            // 더 가벼움 - 단순히 메인 스레드로 전환만 함
            await MainActor.run {
                self.label.text = "Updated"
            }
            
            // 더 무거움 - 새로운 Task 생성 필요
            Task { @MainActor in
                self.label.text = "Updated"
            }
        }
    }
    ```
    
4. 에러 처리
    
    ```swift
    // MainActor.run은 throwing 버전이 있음
    func example2() async throws {
        try await MainActor.run {
            throw SomeError()
        }
    }
    
    // Task는 생성 시점에서 에러를 캐치할 수 없음
    func example3() async {
        Task { @MainActor in
            throw SomeError() // 이 에러는 Task 내부에서 처리해야 함
        }
    }
    ```
    
- MainActor.run 사용이 좋은 경우
    
    ```swift
    // 1. 단순히 UI 업데이트만 필요할 때
    await MainActor.run {
        updateUI()
    }
    
    // 2. 부모 Task의 취소 상태를 유지해야 할 때
    try await someWork()
    await MainActor.run {
        showResult()
    }
    
    // 3. 연속된 메인 액터 작업이 필요할 때
    await MainActor.run {
        step1()
        step2()
        step3()
    }
    ```
    
- Task { @MainActor in } 사용이 좋은 경우
    
    ```swift
    // 1. 독립적으로 실행되어야 하는 작업
    Task { @MainActor in
        await longRunningUIUpdate()
    }
    
    // 2. 취소가 필요한 작업
    let task = Task { @MainActor in
        await animateProgress()
    }
    // 나중에...
    task.cancel()
    
    // 3. 다른 Task와 독립적인 에러 처리가 필요한 경우
    Task { @MainActor in
        do {
            try await riskyUIUpdate()
        } catch {
            handleError(error)
        }
    }
    ```