## 1. Continuation 코드

```swift
@objc private func task1ButtonTapped() {
    // 1. Creating -> Running
    Task {
        // 2. Running -> Suspended (await로 인해)
        let result = await basicAsyncTask()
        
        // 10. Running (최종 결과 반환 및 UI 업데이트)
        statusLabel.text = "✅ \(result)"
    }
}

private func basicAsyncTask() async -> String {
    // 3. Suspended -> Running (basicAsyncTask 실행)
    
    // 4. Running -> Continuation (withCheckedContinuation 시작)
    return await withCheckedContinuation { continuation in
        // 5. Continuation -> Suspend (DispatchQueue 시작)
        DispatchQueue.global().async {
            // 6. Suspended (계산 작업 수행)
            var sum = 0
            for i in 0...100_000 { sum += i }
            
            // 7. Suspended -> Running (continuation.resume 호출)
            continuation.resume(returning: String(sum))
        }
        // 8. Suspend (DispatchQueue 작업 완료 대기)
    }
    // 9. Running -> Suspend (Task 완료)
}

```

![스크린샷 2024-11-15 오전 9.22.33.png](https://prod-files-secure.s3.us-west-2.amazonaws.com/995d9ee3-0dee-48df-b4d6-d85ab76469d2/8feb0654-77ca-44e0-b7cf-54be4520a1d0/%E1%84%89%E1%85%B3%E1%84%8F%E1%85%B3%E1%84%85%E1%85%B5%E1%86%AB%E1%84%89%E1%85%A3%E1%86%BA_2024-11-15_%E1%84%8B%E1%85%A9%E1%84%8C%E1%85%A5%E1%86%AB_9.22.33.png)
```swift
@objc private func task1ButtonTapped() {
    Task {
        // 2. Running -> Suspended (await로 인해)
        let result = await basicAsyncTask()
        
        // 10. Running (최종 결과 반환 및 UI 업데이트)
        statusLabel.text = "✅ \(result)"
    }
}

private func basicAsyncTask() async -> String {
    // 3. Suspended -> Running (basicAsyncTask 실행)
    
    // 4. Running -> Continuation (withCheckedContinuation 시작)
    return await withCheckedContinuation { continuation in
        // 5. Continuation -> Suspend (DispatchQueue 시작)
        DispatchQueue.global().async {
            // 6. Suspended (계산 작업 수행)
            var sum = 0
            for i in 0...100_000 { sum += i }
            
            // 7. Suspended -> Running (continuation.resume 호출)
            continuation.resume(returning: String(sum))
        }
        // 8. Suspend (DispatchQueue 작업 완료 대기)
    }
    // 9. Running -> Suspend (Task 완료)
}
```

- 스레드는 어떻게 동작할까?
    - Creating에서 과정 중간 쯤 새로운 스레드를 만듦 `0x28233a7d`
    - Running → Blocked 를 반복하다가  3. Suspended -> Running (basicAsyncTask 실행)에서 동작 안하다가 Continuation 중간쯤 다시 활성화가 된다.
    - 3번 과정에서부터 ContextSwitches 비용이 많이 발생
        
        ![스크린샷 2024-11-15 오전 10.01.00.png](https://prod-files-secure.s3.us-west-2.amazonaws.com/995d9ee3-0dee-48df-b4d6-d85ab76469d2/c60ea36d-4ef5-4db0-982c-0fd9f0d1aff0/%E1%84%89%E1%85%B3%E1%84%8F%E1%85%B3%E1%84%85%E1%85%B5%E1%86%AB%E1%84%89%E1%85%A3%E1%86%BA_2024-11-15_%E1%84%8B%E1%85%A9%E1%84%8C%E1%85%A5%E1%86%AB_10.01.00.png)
        
- 작업이 끝나면 Context Switches 그대로

## 2. Task.detached 코드

```swift
@objc private func task1ButtonTapped() {
        Task { 
            let result = await basicAsyncTask()
            statusLabel.text = "✅ \(result)"
        }
    }

    private func basicAsyncTask() async -> String {
        let result = await Task.detached(priority: .userInitiated) {
            var sum = 0
            for i in 0...100_000 { sum += i }
            return String(sum)
        }.value
        
        return result
    }
```

![스크린샷 2024-11-15 오전 10.06.13.png](https://prod-files-secure.s3.us-west-2.amazonaws.com/995d9ee3-0dee-48df-b4d6-d85ab76469d2/696c15e3-787c-4e4c-bb7d-2849c548d581/%E1%84%89%E1%85%B3%E1%84%8F%E1%85%B3%E1%84%85%E1%85%B5%E1%86%AB%E1%84%89%E1%85%A3%E1%86%BA_2024-11-15_%E1%84%8B%E1%85%A9%E1%84%8C%E1%85%A5%E1%86%AB_10.06.13.png)

- Continuation과 달리 Waiting이 새로 생겼는데 Task.detached는 새로운 Task를 생성하고 그 결과값 (.value)를 기다려야 하므로 Waiting 상태가 필요하다.
- Runinng 중간에 Creating이 생성된다.
    - task1ButtonTapped() / basicAsyncTask() 각기 다른 Task를 생성하므로 Creating이 두 번 된다.
    - 새로운 스레드를 생성해서 연산 작업 진행

? Continuation에서는 Creating 과정에서 연산하는 스레드를 생성했는데 Task는 다른가?

## 3. Task.sleep()

```swift
  @objc private func task1ButtonTapped() {
        Task {
            let result = await basicAsyncTask()
            await MainActor.run {
                statusLabel.text = "Completed: \(result)"
             }
        }
    }

    private func basicAsyncTask() async -> String {
        let result = await Task.detached(priority: .userInitiated) {
            var sum = 0
            for i in 0...100_000 { sum += i }
            return sum
        }.value
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        return String(sum)
    }
```

![스크린샷 2024-11-15 오전 10.27.45.png](https://prod-files-secure.s3.us-west-2.amazonaws.com/995d9ee3-0dee-48df-b4d6-d85ab76469d2/470a3995-27da-43b9-be7b-53bbbc273bc9/%E1%84%89%E1%85%B3%E1%84%8F%E1%85%B3%E1%84%85%E1%85%B5%E1%86%AB%E1%84%89%E1%85%A3%E1%86%BA_2024-11-15_%E1%84%8B%E1%85%A9%E1%84%8C%E1%85%A5%E1%86%AB_10.27.45.png)

![스크린샷 2024-11-15 오전 10.26.51.png](https://prod-files-secure.s3.us-west-2.amazonaws.com/995d9ee3-0dee-48df-b4d6-d85ab76469d2/e25a9acb-b08b-4ac8-aae0-0e059d1cde89/%E1%84%89%E1%85%B3%E1%84%8F%E1%85%B3%E1%84%85%E1%85%B5%E1%86%AB%E1%84%89%E1%85%A3%E1%86%BA_2024-11-15_%E1%84%8B%E1%85%A9%E1%84%8C%E1%85%A5%E1%86%AB_10.26.51.png)

- 메인스레드, 2번 스레드, 8번 스레드 총 3개의 스레드가 동작
    - Creating이 총 세번 되는데 task1ButtonTapped내 Task, basicAsyncTask 내 Task.detached, Task.sleep()
- Continuation이 생성되는 이유
    - Task.sleep() 내부 코드를 살펴보면 내부에서 `try await withUnsafeThrowingContinuation` 호출을 통해 continuation이 동작하는게 보이는데 위 사진의 Continuation 같긴함

![스크린샷 2024-11-14 오후 6.54.32.png](https://prod-files-secure.s3.us-west-2.amazonaws.com/995d9ee3-0dee-48df-b4d6-d85ab76469d2/97c8504f-5c15-406e-bb2d-110581367dd3/%E1%84%89%E1%85%B3%E1%84%8F%E1%85%B3%E1%84%85%E1%85%B5%E1%86%AB%E1%84%89%E1%85%A3%E1%86%BA_2024-11-14_%E1%84%8B%E1%85%A9%E1%84%92%E1%85%AE_6.54.32.png)

- Continuation 동작과 동시에 Creating이 1초 같이 동작
    - 무엇이 Creating 되는거지?
        - basicAsyncTask 내 Task.sleep()이 Creating 되는 것 같음
            
            ![스크린샷 2024-11-15 오전 10.47.12.png](https://prod-files-secure.s3.us-west-2.amazonaws.com/995d9ee3-0dee-48df-b4d6-d85ab76469d2/2490fc0b-cc85-4e5f-83ac-99dad30ef232/%E1%84%89%E1%85%B3%E1%84%8F%E1%85%B3%E1%84%85%E1%85%B5%E1%86%AB%E1%84%89%E1%85%A3%E1%86%BA_2024-11-15_%E1%84%8B%E1%85%A9%E1%84%8C%E1%85%A5%E1%86%AB_10.47.12.png)
            
- 스레드에서 Preempted 으로 동작 (노란색)
    - preemption(선점)이란, 어느 thread가 수행 중인데, 느닷없이 그 thread가 동작을 멈추고 다른 thread가 수행되는 것을 말한다.
    - 그럼 왜 Preempted가 되는건지?
        - Task.detached(priority: .userInitiated) 해당 작업을 수행하는 스레드임
        1. MainThread에서 작업을 수행하는 중에 작업 2가 비동기로 호출
        2. 메인쓰레드는 Blocking 되고 2번 스레드로 Context Switching 발생
        3. 작업 2가 완료되면 결과값을 MainThread로 반환
        4. Preempting Scheduling을 통해서 각 작업에 대해 얼만큼 수행할 지 또는 어떤 작업을 먼저 수행할 지 결정 그에 맞게 동시성 보장
        - 이게 맞나?
        - 근데 이때 ContextSwitching 비중이 높긴함
        
        ![스크린샷 2024-11-15 오전 10.53.58.png](https://prod-files-secure.s3.us-west-2.amazonaws.com/995d9ee3-0dee-48df-b4d6-d85ab76469d2/79c195c0-8576-445c-8421-40aef05be261/%E1%84%89%E1%85%B3%E1%84%8F%E1%85%B3%E1%84%85%E1%85%B5%E1%86%AB%E1%84%89%E1%85%A3%E1%86%BA_2024-11-15_%E1%84%8B%E1%85%A9%E1%84%8C%E1%85%A5%E1%86%AB_10.53.58.png)
        
    

## 4. Task.sleep()

- Task내부에 Task.sleep(nanoseconds: 1_000_000_000)

```swift
 @objc private func task1ButtonTapped() {
        Task {
            let result = await basicAsyncTask()
            await MainActor.run {
                statusLabel.text = "Completed: \(result)"
             }
        }
    }

    private func basicAsyncTask() async -> String {
        let result = await Task.detached(priority: .userInitiated) {
            var sum = 0
            for i in 0...100_000 { sum += i }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return sum
        }.value
        
        return String(sum)
    }
```

- 예상되는 결과값을 먼저 생각해보자
    - 

![스크린샷 2024-11-15 오전 11.07.21.png](https://prod-files-secure.s3.us-west-2.amazonaws.com/995d9ee3-0dee-48df-b4d6-d85ab76469d2/758fdc2f-6f1b-4c92-a9c3-b109ff56bfb2/%E1%84%89%E1%85%B3%E1%84%8F%E1%85%B3%E1%84%85%E1%85%B5%E1%86%AB%E1%84%89%E1%85%A3%E1%86%BA_2024-11-15_%E1%84%8B%E1%85%A9%E1%84%8C%E1%85%A5%E1%86%AB_11.07.21.png)

![스크린샷 2024-11-15 오전 11.07.46.png](https://prod-files-secure.s3.us-west-2.amazonaws.com/995d9ee3-0dee-48df-b4d6-d85ab76469d2/a141735e-bbcd-4859-84ee-c966f20680d8/%E1%84%89%E1%85%B3%E1%84%8F%E1%85%B3%E1%84%85%E1%85%B5%E1%86%AB%E1%84%89%E1%85%A3%E1%86%BA_2024-11-15_%E1%84%8B%E1%85%A9%E1%84%8C%E1%85%A5%E1%86%AB_11.07.46.png)

- 벌써 끔찍하다

## 5. 반복문 안에 Task.sleep()

```swift
   @objc private func task1ButtonTapped() {
        Task {
            let result = await basicAsyncTask()
            await MainActor.run {
                statusLabel.text = "Completed: \(result)"
             }
        }
    }

    private func basicAsyncTask() async -> String {
        let result = await Task.detached(priority: .userInitiated) {
            var sum = 0
            for i in 0...5 {
                sum += i
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            return sum
        }.value
        
        return String(result)
    }
```

![스크린샷 2024-11-15 오후 12.56.59.png](https://prod-files-secure.s3.us-west-2.amazonaws.com/995d9ee3-0dee-48df-b4d6-d85ab76469d2/632b0f22-8c43-40b9-8beb-d8ca67513fc8/%E1%84%89%E1%85%B3%E1%84%8F%E1%85%B3%E1%84%85%E1%85%B5%E1%86%AB%E1%84%89%E1%85%A3%E1%86%BA_2024-11-15_%E1%84%8B%E1%85%A9%E1%84%92%E1%85%AE_12.56.59.png)

![스크린샷 2024-11-15 오후 12.57.28.png](https://prod-files-secure.s3.us-west-2.amazonaws.com/995d9ee3-0dee-48df-b4d6-d85ab76469d2/a472b62d-a6b7-42c7-ac52-56440f465079/%E1%84%89%E1%85%B3%E1%84%8F%E1%85%B3%E1%84%85%E1%85%B5%E1%86%AB%E1%84%89%E1%85%A3%E1%86%BA_2024-11-15_%E1%84%8B%E1%85%A9%E1%84%92%E1%85%AE_12.57.28.png)[bbd6a743-7079-4753-8879-e33117ddf5db_섹션8._swift_concurrency_방식으로의_전환.pdf](https://github.com/user-attachments/files/17767944/bbd6a743-7079-4753-8879-e33117ddf5db_.8._swift_concurrency_._.pdf)
