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
    - 3번 과정에서부터 ContextSwitches 비용이 많이 발생
        <img width="655" alt="스크린샷 2024-11-16 오후 3 22 53" src="https://github.com/user-attachments/assets/44092a20-5e25-4416-b12b-a741a8df162a">        
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
<img width="707" alt="스크린샷 2024-11-16 오후 3 23 27" src="https://github.com/user-attachments/assets/cc1effb5-dae8-4dec-a730-83c6fb8fb737">


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
<img width="709" alt="스크린샷 2024-11-16 오후 3 24 05" src="https://github.com/user-attachments/assets/8021d353-5481-4d59-9c4e-e1faf870de76">
<img width="706" alt="스크린샷 2024-11-16 오후 3 24 28" src="https://github.com/user-attachments/assets/905b9b3d-f538-4a58-916b-d0125b53602a">


- 메인스레드, 2번 스레드, 8번 스레드 총 3개의 스레드가 동작
    - Creating이 총 세번 되는데 task1ButtonTapped내 Task, basicAsyncTask 내 Task.detached, Task.sleep()
- Continuation이 생성되는 이유
    - Task.sleep() 내부 코드를 살펴보면 내부에서 `try await withUnsafeThrowingContinuation` 호출을 통해 continuation이 동작하는게 보이는데 위 사진의 Continuation 같긴함
    <img width="636" alt="스크린샷 2024-11-16 오후 3 26 32" src="https://github.com/user-attachments/assets/4be6315c-50d7-4f11-88a1-30bbfc9ee1b2">

- Continuation 동작과 동시에 Creating이 1초 같이 동작
    - 무엇이 Creating 되는거지?
        - basicAsyncTask 내 Task.sleep()이 Creating 되는 것 같음
    <img width="412" alt="스크린샷 2024-11-16 오후 3 26 44" src="https://github.com/user-attachments/assets/e76e5853-7044-42a0-982c-4c8f4c3a7b13">

            
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
        <img width="591" alt="스크린샷 2024-11-16 오후 3 27 03" src="https://github.com/user-attachments/assets/a096e534-1e03-467b-9738-ab49d0af904e">

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

