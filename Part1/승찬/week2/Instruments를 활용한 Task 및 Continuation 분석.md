## Swift Concurrency를 사용한 Task 및 Continuation 동작 원리 분석
- 공통 코드는 버튼을 클릭했을 때, 0~100,000까지 계산해서 UILabel에 업데이트한다.
- Continuation의 생성과 어떤 코드에서 어떤 동작을 할 지, 예측 및 분석한다.
- Concurrency 동작에 따라 Context Switching 비용 분석과 어느 Thread에서 동작하는지 살펴본다.

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
<img width="710" alt="스크린샷 2024-11-16 오후 3 22 10" src="https://github.com/user-attachments/assets/3a57d108-70f3-4a64-9b36-e6447b3eebfa">

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
    - 3번 과정에서부터 ContextSwitches 비용이 기존보다 많이 발생한다.
    - 그 이유를 예측해보면 MainThread에서 버튼 탭이 동작하고, 연산하는 과정을 다른 스레드로 보내는 과정에서 비용 발생이 생기는 것 같다.
        <img width="655" alt="스크린샷 2024-11-16 오후 3 22 53" src="https://github.com/user-attachments/assets/44092a20-5e25-4416-b12b-a741a8df162a">        
- 작업이 끝나면 Context Switching 기존과 동일하게 유지한다.

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
<img width="707" alt="스크린샷 2024-11-16 오후 3 23 27" src="https://github.com/user-attachments/assets/cc1effb5-dae8-4dec-a730-83c6fb8fb737">


- Continuation 생성과 달리 Waiting이라는 것이 새로 생겼다.
- Task.detached는 새로운 Task를 생성하고 그 결과값 (.value)를 기다려야 하므로 Waiting 상태가 필요하다. (결과값 받기까지 대기 상태)
- Runinng 중간에 Creating이 생성된다.
    - task1ButtonTapped() / basicAsyncTask() 각기 다른 Task를 생성하므로 Creating이 두 번 된다.
    - 새로운 스레드를 생성해서 연산 작업 진행

- Continuation에서는 Creating 과정에서 연산하는 스레드를 생성했는데 Task는 다른가?
- 스터디에서 Task를 생성하면 무조건 Continuation이 생성되는 것이 아닌가? 혹은 Task내 작업에서 비동기 작업에서 Continuation이 생성되는 것이 아닐까? 라는 이야기를 나눴었다.
- 3번의 Task.sleep() 코드를 보면 이해가 될 것 같다.

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
<img width="709" alt="스크린샷 2024-11-16 오후 3 24 05" src="https://github.com/user-attachments/assets/8021d353-5481-4d59-9c4e-e1faf870de76">
<img width="706" alt="스크린샷 2024-11-16 오후 3 24 28" src="https://github.com/user-attachments/assets/905b9b3d-f538-4a58-916b-d0125b53602a">


- 메인스레드, 2번 스레드, 8번 스레드 총 3개의 스레드가 동작한다. (2, 8번 스레드라고 하겠다.)
    - Creating이 총 세번 발생한다. task1ButtonTapped내 Task, basicAsyncTask 내 Task.detached, Task.sleep()
- Continuation이 생성되는 이유
    - Task.sleep() 내부 코드를 살펴보면 내부에서 `try await withUnsafeThrowingContinuation` 호출을 통해 continuation이 동작하는게 보이는데 위 사진의 Continuation 이라고 예측할 수 있다.
    <img width="636" alt="스크린샷 2024-11-16 오후 3 26 32" src="https://github.com/user-attachments/assets/4be6315c-50d7-4f11-88a1-30bbfc9ee1b2">
    - 즉, 2번 예시에서 예측했던 내부 동작에서 Continuation이 생성되는 것으로, Continuation 생성이 Task와 직접적인 관계가 없는 것 같다. (AsyncStream 제외)
- Task.sleep()을 호출하게 되면 Continuation이 1초 동작하는데 그에 따라 Creating도 1초 동작한다.
    - 그렇다면 무엇이 Creating 되는 것인가?
        - basicAsyncTask 내 Task.sleep()이 Creating 된다. (Task가 호출될 때, Creating이 발생하므로)
    <img width="412" alt="스크린샷 2024-11-16 오후 3 26 44" src="https://github.com/user-attachments/assets/e76e5853-7044-42a0-982c-4c8f4c3a7b13">

            
- 스레드에서 Preempted 이 새로 생긴 것을 확인할 수 있다. (노란색)
    - preemption(선점)이란, 어느 thread가 수행 중인데, 느닷없이 그 thread가 동작을 멈추고 다른 thread가 수행되는 것을 말한다.
    - 그럼 왜 Preempted가 되는것일까>
        - Task.detached(priority: .userInitiated) 해당 작업을 수행하는 스레드임
        1. MainThread에서 작업을 수행하는 중에 작업 2가 비동기로 호출
        2. 메인쓰레드는 Blocking 되고 2번 스레드로 Context Switching 발생
        3. 작업 2가 완료되면 결과값을 MainThread로 반환
        4. Preempting Scheduling을 통해서 각 작업에 대해 얼만큼 수행할 지 또는 어떤 작업을 먼저 수행할 지 결정 그에 맞게 동시성 보장
        - 이런 원리로 선점이 발생하는 것 같다.
        - 근데 이때 Context Switching 비용이 기존보다 많이 발생한다. 
        <img width="591" alt="스크린샷 2024-11-16 오후 3 27 03" src="https://github.com/user-attachments/assets/a096e534-1e03-467b-9738-ab49d0af904e">

## 4. Task.sleep()
- 3번 예시와 다르게 Task내부에 Task.sleep(nanoseconds: 1_000_000_000) 선언했다.
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

<img width="636" alt="스크린샷 2024-11-16 오후 3 27 28" src="https://github.com/user-attachments/assets/12c74bf6-dc45-4ffa-8ecd-803bcca2c5be">
<img width="639" alt="스크린샷 2024-11-16 오후 3 27 43" src="https://github.com/user-attachments/assets/145c3d6b-8612-4ff6-9dfd-9f15e3adfaeb">

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
<img width="638" alt="스크린샷 2024-11-16 오후 3 28 00" src="https://github.com/user-attachments/assets/34381f86-957e-4930-9659-08e73425179b">

