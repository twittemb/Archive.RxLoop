//
//  Loop.swift
//  RxLoop
//
//  Created by Thibault Wittemberg on 2019-02-03.
//  Copyright © 2019 WarpFactor. All rights reserved.
//
import RxSwift
import RxCocoa

typealias FeatureToIntent<StateType: State, IntentType: Intent> = (Observable<StateType>) -> Observable<IntentType>
typealias IntentToAction<IntentType: Intent, ActionType: Action> = (Observable<IntentType>) -> Observable<ActionType>
typealias ActionToState<ActionType: Action, StateType: State> = (Observable<(ActionType, StateType)>) -> Observable<StateType>
typealias StateToFeature<StateType: State> = (StateType) -> Void

class LoopRuntime<StateType: State> {
    private let loop: Observable<StateType>
    private let state: PublishRelay<StateType>
    init(with loop: Observable<StateType>, and state: PublishRelay<StateType>) {
        self.loop = loop
        self.state = state
    }

    func start () -> Disposable {
        return self.loop.bind(to: state)
    }

    func start(when trigger: Completable) -> Disposable {
        return trigger.andThen(self.loop).bind(to: self.state)
    }
}

func loop<IntentType: Intent, ActionType: Action, StateType: State> (featureToIntent: @escaping FeatureToIntent<StateType, IntentType>,
                                                                     intentToAction: @escaping IntentToAction<IntentType, ActionType>,
                                                                     actionToState: @escaping ActionToState<ActionType, StateType>)
    -> (StateType, @escaping StateToFeature<StateType>) -> LoopRuntime<StateType> {

        func actionToActionAndState(actions: Observable<ActionType>, states: Observable<StateType>) -> Observable<(ActionType, StateType)> {
            return actions.withLatestFrom(states) { ($0, $1) }
        }

        return { (initialState: StateType, stateToFeature: @escaping StateToFeature<StateType>) -> LoopRuntime<StateType> in
            let state = PublishRelay<StateType>()
            let initialStateObservable = state.startWith(initialState)
            let featuresToActions = compose(f1: featureToIntent, f2: intentToAction)
            let featuresToActionAndStates = composeBis(f1: featuresToActions, f2: actionToActionAndState)
            let featuresToStates = composeTer(f1: featuresToActionAndStates, f2: actionToState)
            let loop = featuresToStates(initialStateObservable, initialStateObservable).do(onNext: stateToFeature)
            return LoopRuntime(with: loop, and: state)
            //            return featuresToStates(initialStateObservable, initialStateObservable).do(onNext: stateToFeature).bind(to: state)
        }
}

func preloop<IntentType: Intent, ActionType: Action, StateType: State> (intentToAction: @escaping IntentToAction<IntentType, ActionType>,
                                                                        actionToState: @escaping ActionToState<ActionType, StateType>)
    -> (@escaping FeatureToIntent<StateType, IntentType>) -> (StateType, @escaping StateToFeature<StateType>) -> LoopRuntime<StateType> {

        func actionToActionAndState(actions: Observable<ActionType>, states: Observable<StateType>) -> Observable<(ActionType, StateType)> {
            return actions.withLatestFrom(states) { ($0, $1) }
        }

        return { (featureToIntent: @escaping FeatureToIntent<StateType, IntentType>) in
            return { (initialState: StateType, stateToFeature: @escaping StateToFeature<StateType>) -> LoopRuntime<StateType> in
                let state = PublishRelay<StateType>()
                let initialStateObservable = state.startWith(initialState)
                let featuresToActions = compose(f1: featureToIntent, f2: intentToAction)
                let featuresToActionAndStates = composeBis(f1: featuresToActions, f2: actionToActionAndState)
                let featuresToStates = composeTer(f1: featuresToActionAndStates, f2: actionToState)
                let loop = featuresToStates(initialStateObservable, initialStateObservable).do(onNext: stateToFeature)
                return LoopRuntime(with: loop, and: state)
                //                return featuresToStates(initialStateObservable, initialStateObservable).do(onNext: stateToFeature).bind(to: state)
            }
        }


}

func compose<A, B, C> (f1: @escaping (A) -> B, f2: @escaping (B) -> C) -> (A) -> C {
    return { (a: A) -> C in
        return f2(f1(a))
    }
}

func composeBis<A, B, C, D> (f1: @escaping (A) -> B, f2: @escaping (B, C) -> D) -> (A, C) -> D {
    return { (a: A, c: C) -> D in
        return f2(f1(a), c)
    }
}

func composeTer<A, B, C, D> (f1: @escaping (A, B) -> C, f2: @escaping (C) -> D) -> (A, B) -> D {
    return { (a: A, b: B) -> D in
        return f2(f1(a, b))
    }
}

func flatten<A, B> (funcs: [(A) -> B]) -> (A) -> [B] {
    return { (a: A) -> [B] in
        return funcs.map { $0(a) }
    }
}

func merge<A, B> (_ funcs: ((A) -> B)...) -> (A) -> B where A: ObservableType, B: ObservableType {

    func observableMerge(inputs: [B]) -> B {
        return Observable<B.E>.merge(inputs.map { $0.asObservable() }) as! B
    }


    let flatFuncs = flatten(funcs: funcs)
    return compose(f1: flatFuncs, f2: observableMerge)
}

func merge<A> (_ funcs: ((A) -> Void)...) -> (A) -> Void {
    return { (a:A) in
        funcs.forEach { $0(a) }
    }
}
