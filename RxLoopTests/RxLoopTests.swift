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
@testable import RxLoop

protocol Intent: Equatable {}

protocol Action: Equatable {}

struct TestIntent: Intent {
    let name: String
}

struct TestAction: Action {
    let name: String
}

struct TestState: State {
    let name: String
}

class RxLoopTests: XCTestCase {

    var disposeBag: DisposeBag? = DisposeBag()

    func featureToIntent1 (state: Observable<TestState>) -> Observable<TestIntent> {
        return Observable<Int>
            .interval(2, scheduler: MainScheduler.instance)
            .map { timer in return TestIntent(name: "1: \(timer)") }
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
        return intent.map { intent in return TestAction(name: intent.name) }
    }

    func actionToState (actionAndState: Observable<(TestAction, TestState)>) -> Observable<TestState> {
        return actionAndState.map { (action, state) in return TestState(name: "\(state.name) \(action.name)") }
    }

    func stateToFeature1 (state: TestState) {
        print ("----------- 1: handle side effect for state: \(state)")
    }

    func stateToFeature2 (state: TestState) {
        print ("----------- 2: handle side effect for state: \(state)")
    }

    func testExample() {
        let exp = expectation(description: "")

        let myLoop = loop(stateBinder: featureToIntent1,
                          mutationEmitter: intentToAction,
                          reducer: actionToState,
                          stateInterpreter: stateToFeature1)
        myLoop(TestState(name: "Initial State")).start().disposed(by: self.disposeBag!)
        exp.fulfill()
        waitForExpectations(timeout: 5)

        // break the loop
        self.disposeBag = nil
        let exp2 = expectation(description: "")
        waitForExpectations(timeout: 5)
    }

    func testExample2() {
        let exp = expectation(description: "")
        let trigger = Observable<Void>.just(()).delay(5, scheduler: MainScheduler.instance).asSingle().asCompletable()
        let myLoop = loop(stateBinder: featureToIntent1,
                          mutationEmitter: intentToAction,
                          reducer: actionToState,
                          stateInterpreter: stateToFeature1)
        myLoop(TestState(name: "Initial State")).start(when: trigger).disposed(by: self.disposeBag!)
        waitForExpectations(timeout: 20)
    }

    func testExample3() {
        let exp = expectation(description: "")
        let myLoop = loop(stateBinder: featureToIntent1,
                          mutationEmitter: intentToAction,
                          reducer: actionToState,
                          stateInterpreter: stateToFeature1)
        myLoop(TestState(name: "Initial State")).start(after: 3).disposed(by: self.disposeBag!)
        waitForExpectations(timeout: 20)
    }

    func testExample4() {
        let exp = expectation(description: "")
        let featureToIntents = merge(featureToIntent1, featureToIntent2)
        let stateToFeatures = merge(stateToFeature1, stateToFeature2)
        let myLoop = loop(stateBinder: featureToIntents,
                          mutationEmitter: intentToAction,
                          reducer: actionToState,
                          stateInterpreter: stateToFeatures)
        myLoop(TestState(name: "Initial State")).start().disposed(by: self.disposeBag!)

        waitForExpectations(timeout: 30)
    }
}
