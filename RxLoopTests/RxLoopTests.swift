//
//  RxLoopTests.swift
//  RxLoopTests
//
//  Created by Thibault Wittemberg on 2019-02-03.
//  Copyright © 2019 WarpFactor. All rights reserved.
//

import XCTest
import RxSwift
import RxCocoa
import Foundation
@testable import RxLoop

protocol Intent: Equatable {}

protocol Action: Equatable {}

struct TestIntent: Intent {
    let name: String
}

struct TestAction: Action {
    let name: String
}

struct TestState {
    let name: String
}

class RxLoopTests: XCTestCase {

    func currentQueueName() -> String? {
        let name = __dispatch_queue_get_label(nil)
        return String(cString: name, encoding: .utf8)
    }

    var disposeBag: DisposeBag? = DisposeBag()

    func featureToIntent1 (state: Observable<TestState>) -> Observable<TestIntent> {
        return Observable<Int>
            .interval(2, scheduler: MainScheduler.instance)
            .map { timer in
                print("featureToIntent1 -> Queue: \(self.currentQueueName() ?? "queue")")
                return TestIntent(name: "1: \(timer)")
            }
            .startWith(TestIntent(name: "1: 0"))

//        return state.do(onNext: { state in print ("intent with State: \(state)") }).map { _ in return TestIntent() }


//        return Observable<Int>.interval(2, scheduler: MainScheduler.instance).withLatestFrom(state, resultSelector: { (timer, state) -> TestIntent in
//            return TestIntent(name: "\(timer)")
//        })
//        return Observable.zip(state, Observable<Int>.interval(2, scheduler: MainScheduler.instance)) { (state, timer) -> TestIntent in
//            return TestIntent(name: "\(timer)")
//        }
    }

    func featureToIntent2 (state: Observable<TestState>) -> Observable<TestIntent> {
//        return Observable<TestIntent>.just(TestIntent(name: "Intent 2"))
        return Observable<Int>.interval(5, scheduler: MainScheduler.instance).map { timer in return TestIntent(name: "2: \(timer)") }
        //        return state.do(onNext: { state in print ("intent with State: \(state)") }).map { _ in return TestIntent() }


        //        return Observable<Int>.interval(2, scheduler: MainScheduler.instance).withLatestFrom(state, resultSelector: { (timer, state) -> TestIntent in
        //            return TestIntent(name: "\(timer)")
        //        })
        //        return Observable.zip(state, Observable<Int>.interval(2, scheduler: MainScheduler.instance)) { (state, timer) -> TestIntent in
        //            return TestIntent(name: "\(timer)")
        //        }
    }

    func intentToAction (intent: Observable<TestIntent>) -> Observable<TestAction> {
        return intent
            .observeOn(SerialDispatchQueueScheduler.init(qos: .userInteractive))
            .map { intent in
            print("intentToAction -> Queue: \(self.currentQueueName() ?? "queue")")
            return TestAction(name: intent.name)
        }
    }

    func actionToState (actionAndState: Observable<(TestAction, TestState)>) -> Observable<TestState> {
        return actionAndState.map { (action, state) in
            print("actionToState -> Queue: \(self.currentQueueName() ?? "queue")")
            return TestState(name: "\(state.name) \(action.name)")
        }
    }

    func stateToFeature1 (state: TestState) {
        print("stateToFeature1 -> Queue: \(self.currentQueueName() ?? "queue")")
        print ("----------- 1: handle side effect for state: \(state)")
    }

    func stateToFeature2 (state: TestState) {
        print ("----------- 2: handle side effect for state: \(state)")
    }

    func testExample() {
        let exp = expectation(description: "")

        let myLoop = loop(mutationEmitter: compose(f1: featureToIntent1, f2: intentToAction),
                          reducer: actionToState)
        myLoop(TestState(name: "Initial State"), stateToFeature1).start().disposed(by: self.disposeBag!)
        exp.fulfill()
        waitForExpectations(timeout: 5)

        // break the loop
        self.disposeBag = nil
        let exp2 = expectation(description: "")
        waitForExpectations(timeout: 5)
    }

    func testExample2() {
        let exp = expectation(description: "")
        let trigger = Observable<Void>.just(()).delay(10, scheduler: MainScheduler.instance)
        let myLoop = loop(mutationEmitter: compose(f1: featureToIntent1, f2: intentToAction),
                          reducer: actionToState)
        myLoop(TestState(name: "Initial State"), stateToFeature1).start(when: trigger).disposed(by: self.disposeBag!)
        waitForExpectations(timeout: 20)
    }

    func testExample3() {
        let exp = expectation(description: "")
        let myLoop = loop(mutationEmitter: compose(f1: featureToIntent1, f2: intentToAction),
                          reducer: actionToState)
        myLoop(TestState(name: "Initial State"), stateToFeature1).start(after: .seconds(5)).disposed(by: self.disposeBag!)
        waitForExpectations(timeout: 20)
    }

    func testExample4() {
        let exp = expectation(description: "")
        let featureToIntents = merge(featureToIntent1, featureToIntent2)
        let stateToFeatures = concat(stateToFeature1, stateToFeature2)
        let myLoop = loop(mutationEmitter: compose(f1: featureToIntents, f2: intentToAction),
                          reducer: actionToState)
        myLoop(TestState(name: "Initial State"), stateToFeatures).start().disposed(by: self.disposeBag!)

        waitForExpectations(timeout: 30)
    }

    func testExample5() {
        let exp = expectation(description: "")

        let completable = Observable<Int>.interval(5, scheduler: MainScheduler.instance).take(1)

        let myLoop = loop(mutationEmitter: compose(f1: featureToIntent1, f2: intentToAction),
                          reducer: actionToState)
        _ = myLoop(TestState(name: "Initial State"), stateToFeature1).take(until: completable).start()
        waitForExpectations(timeout: 20)
    }
}
