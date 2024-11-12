import UIKit
import Foundation


enum CookingError: Error {
    case outOfWater
    case noodleBroken
    case soupTooSpicy
}

actor RamenCooking {
    private var waterAmount = 10 // 사용 가능한 물의 양
    
    // 물 사용량 체크 및 차감
    private func useWater(cups: Int) throws {
        guard waterAmount >= cups else {
            throw CookingError.outOfWater
        }
        waterAmount -= cups
    }
    
    func boilWater(cups: Int) async throws -> Bool {
        try useWater(cups: cups)
        print("🌊 물을 끓이는 중...")
        try await Task.sleep(for: .seconds(3))
        print("♨️ 물이 끓었습니다!")
        return true
    }
    
    func addIngredients() async throws {
        print("🍜 면과 스프를 넣는 중...")
        try await Task.sleep(for: .seconds(1))
        print("✅ 재료를 모두 넣었습니다!")
    }
    
    func cookNoodles() async throws -> Bool {
        print("⏰ 면을 익히는 중...")
        try await Task.sleep(for: .seconds(4))
        print("✨ 면이 다 익었습니다!")
        return true
    }
    
    func addEgg() async throws {
        print("🥚 계란을 넣는 중...")
        try await Task.sleep(for: .seconds(1))
        print("✅ 계란을 넣었습니다!")
    }
    
    func finishCooking(ramenNumber: Int) async -> String {
        return "🍜 \(ramenNumber)번 라면이 완성되었습니다!"
    }
}

// 단일 라면 끓이기 함수
func cookSingleRamen(ramenCooking: RamenCooking, ramenNumber: Int) async {
    do {
        print("📍 \(ramenNumber)번 라면 조리 시작")
        try await ramenCooking.boilWater(cups: 2)
        try await ramenCooking.addIngredients()
        try await ramenCooking.cookNoodles()
        try await ramenCooking.addEgg()
        let result = await ramenCooking.finishCooking(ramenNumber: ramenNumber)
        print(result)
    } catch {
        print("❌ \(ramenNumber)번 라면 조리 실패: \(error.localizedDescription)")
    }
}

// 여러 개의 라면을 동시에 끓이는 함수
func cookMultipleRamens() async {
    let ramenCooking = RamenCooking()
    
    // 동시에 여러 라면 끓이기
    async let ramen1: () = cookSingleRamen(ramenCooking: ramenCooking, ramenNumber: 1)
    async let ramen2: () = cookSingleRamen(ramenCooking: ramenCooking, ramenNumber: 2)
    
    // 타이머 시작
    let timerTask = Task {
        for i in 1...10 {
            print("⏱️ 경과 시간: \(i)초")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
    
    // 별도의 Task로 라면 상태 체크
    let checkTask = Task {
        while !Task.isCancelled {
            print("👀 라면 상태 체크 중...")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
    
    // 모든 라면이 완성될 때까지 대기
    await [ramen1, ramen2]
    
    // 상태 체크 Task 취소
    checkTask.cancel()
    
    print("🎉 모든 라면이 완성되었습니다!")
}

// 우선순위가 다른 여러 Task 실행하기
func demonstrateTaskPriorities() async {
    let ramenCooking = RamenCooking()
    
    // 높은 우선순위 Task
    let highPriorityTask = Task(priority: .high) {
        await cookSingleRamen(ramenCooking: ramenCooking, ramenNumber: 1)
    }
    
    // 낮은 우선순위 Task
    let lowPriorityTask = Task(priority: .low) {
        await cookSingleRamen(ramenCooking: ramenCooking, ramenNumber: 2)
    }
    
    // Task 그룹으로 여러 작업 관리하기
    await withTaskGroup(of: Void.self) { group in
        // 여러 개의 라면을 Task 그룹에 추가
        for i in 3...4 {
            group.addTask {
                await cookSingleRamen(ramenCooking: ramenCooking, ramenNumber: i)
            }
        }
    }
}

// 메인 실행 코드

struct RamenApp {
    static func main() async {
        print("=== 일반 라면 끓이기 ===")
        await cookMultipleRamens()
        
        print("\n=== 우선순위가 다른 Task로 라면 끓이기 ===")
        await demonstrateTaskPriorities()
    }
}

Task {
    await RamenApp.main()
}



"""
=== 일반 라면 끓이기 ===
📍 1번 라면 조리 시작
📍 2번 라면 조리 시작
👀 라면 상태 체크 중...
⏱️ 경과 시간: 1초
🌊 물을 끓이는 중...
🌊 물을 끓이는 중...
⏱️ 경과 시간: 2초
👀 라면 상태 체크 중...
⏱️ 경과 시간: 3초
♨️ 물이 끓었습니다!
⏱️ 경과 시간: 4초
♨️ 물이 끓었습니다!
🍜 면과 스프를 넣는 중...
🍜 면과 스프를 넣는 중...
✅ 재료를 모두 넣었습니다!
⏰ 면을 익히는 중...
✅ 재료를 모두 넣었습니다!
⏰ 면을 익히는 중...
👀 라면 상태 체크 중...
⏱️ 경과 시간: 5초
⏱️ 경과 시간: 6초
👀 라면 상태 체크 중...
⏱️ 경과 시간: 7초
⏱️ 경과 시간: 8초
✨ 면이 다 익었습니다!
👀 라면 상태 체크 중...
⏱️ 경과 시간: 9초
✨ 면이 다 익었습니다!
🥚 계란을 넣는 중...
🥚 계란을 넣는 중...
✅ 계란을 넣었습니다!
⏱️ 경과 시간: 10초
✅ 계란을 넣었습니다!
🍜 1번 라면이 완성되었습니다!
🍜 2번 라면이 완성되었습니다!
🎉 모든 라면이 완성되었습니다!

=== 우선순위가 다른 Task로 라면 끓이기 ===
📍 1번 라면 조리 시작
🌊 물을 끓이는 중...
📍 3번 라면 조리 시작
🌊 물을 끓이는 중...
📍 2번 라면 조리 시작
🌊 물을 끓이는 중...
📍 4번 라면 조리 시작
🌊 물을 끓이는 중...
♨️ 물이 끓었습니다!
♨️ 물이 끓었습니다!
♨️ 물이 끓었습니다!
🍜 면과 스프를 넣는 중...
🍜 면과 스프를 넣는 중...
🍜 면과 스프를 넣는 중...
♨️ 물이 끓었습니다!
🍜 면과 스프를 넣는 중...
✅ 재료를 모두 넣었습니다!
⏰ 면을 익히는 중...
✅ 재료를 모두 넣었습니다!
⏰ 면을 익히는 중...
✅ 재료를 모두 넣었습니다!
⏰ 면을 익히는 중...
✅ 재료를 모두 넣었습니다!
⏰ 면을 익히는 중...
✨ 면이 다 익었습니다!
✨ 면이 다 익었습니다!
✨ 면이 다 익었습니다!
🥚 계란을 넣는 중...
🥚 계란을 넣는 중...
🥚 계란을 넣는 중...
✨ 면이 다 익었습니다!
🥚 계란을 넣는 중...
✅ 계란을 넣었습니다!
🍜 3번 라면이 완성되었습니다!
✅ 계란을 넣었습니다!
🍜 1번 라면이 완성되었습니다!
✅ 계란을 넣었습니다!
🍜 4번 라면이 완성되었습니다!
✅ 계란을 넣었습니다!
🍜 2번 라면이 완성되었습니다!
"""

