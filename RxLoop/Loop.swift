//
//  Loop.swift
//  RxLoop
//
//  Created by Thibault Wittemberg on 2019-02-03.
//  Copyright © 2019 WarpFactor. All rights reserved.
//
import RxSwift
import RxCocoa

typealias StateBinder<StateType: State, A> = (Observable<StateType>) -> Observable<A>
typealias Mapper<A, B> = (Observable<A>) -> Observable<B>
typealias MutationEmitter<A, Mutation> = (Observable<A>) -> Observable<Mutation>
typealias Reducer<Mutation, StateType: State> = (Observable<(Mutation, StateType)>) -> Observable<StateType>
typealias StateInterpreter<StateType: State> = (StateType) -> Void

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

    func start(after dueTime: RxTimeInterval, on scheduler: SchedulerType = MainScheduler.instance) -> Disposable {
        let trigger = Single<Void>.just(()).delay(dueTime, scheduler: scheduler).asCompletable()
        return self.start(when: trigger)
    }
}

func loop<Mutation, StateType: State> (stateBinder: @escaping StateBinder<StateType, Mutation>,
                                       reducer: @escaping Reducer<Mutation, StateType>,
                                       stateInterpreter: @escaping StateInterpreter<StateType>) -> (StateType) -> LoopRuntime<StateType> {

    func tuplize(mutations: Observable<Mutation>, states: Observable<StateType>) -> Observable<(Mutation, StateType)> {
        return mutations.withLatestFrom(states) { ($0, $1) }
    }

    return { (initialState: StateType) -> LoopRuntime<StateType> in
        let state = PublishRelay<StateType>()
        let initialStateObservable = state.startWith(initialState)
        let stateBinderToReducer = composeAndAgregate(f1: stateBinder, f2: tuplize)
        let stateBinderToReducedState = composeWithTwoParameters(f1: stateBinderToReducer, f2: reducer) // -> suite de fibonacci: Etat N = Etat 0 + Etat N-1
        let loop = stateBinderToReducedState(initialStateObservable, initialStateObservable).do(onNext: stateInterpreter)
        return LoopRuntime(with: loop, and: state)
    }
}

func loop<A, Mutation, StateType: State> (stateBinder: @escaping StateBinder<StateType, A>,
                                          mutationEmitter: @escaping MutationEmitter<A, Mutation>,
                                          reducer: @escaping Reducer<Mutation, StateType>,
                                          stateInterpreter: @escaping StateInterpreter<StateType>) -> (StateType) -> LoopRuntime<StateType> {

        func tuplize(mutations: Observable<Mutation>, states: Observable<StateType>) -> Observable<(Mutation, StateType)> {
            return mutations.withLatestFrom(states) { ($0, $1) }
        }

        return { (initialState: StateType) -> LoopRuntime<StateType> in
            let state = PublishRelay<StateType>()
            let initialStateObservable = state.startWith(initialState)
            let stateBinderToMutation = compose(f1: stateBinder, f2: mutationEmitter)
            let stateBinderToReducer = composeAndAgregate(f1: stateBinderToMutation, f2: tuplize)
            let stateBinderToReducedState = composeWithTwoParameters(f1: stateBinderToReducer, f2: reducer)
            let loop = stateBinderToReducedState(initialStateObservable, initialStateObservable).do(onNext: stateInterpreter)
            return LoopRuntime(with: loop, and: state)
        }
}

func loop<A, B, Mutation, StateType: State> (stateBinder: @escaping StateBinder<StateType, A>,
                                             mapper: @escaping Mapper<A, B>,
                                             mutationEmitter: @escaping MutationEmitter<B, Mutation>,
                                             reducer: @escaping Reducer<Mutation, StateType>,
                                             stateInterpreter: @escaping StateInterpreter<StateType>) -> (StateType) -> LoopRuntime<StateType> {

        func tuplize(mutations: Observable<Mutation>, states: Observable<StateType>) -> Observable<(Mutation, StateType)> {
            return mutations.withLatestFrom(states) { ($0, $1) }
        }

        return { (initialState: StateType) -> LoopRuntime<StateType> in
            let state = PublishRelay<StateType>()
            let initialStateObservable = state.startWith(initialState)
            let stateBinderToMapper = compose(f1: stateBinder, f2: mapper)
            let stateBinderToMutation = compose(f1: stateBinderToMapper, f2: mutationEmitter)
            let stateBinderToReducer = composeAndAgregate(f1: stateBinderToMutation, f2: tuplize)
            let stateBinderToReducedState = composeWithTwoParameters(f1: stateBinderToReducer, f2: reducer)
            let loop = stateBinderToReducedState(initialStateObservable, initialStateObservable).do(onNext: stateInterpreter)
            return LoopRuntime(with: loop, and: state)
        }
}
