//
//  Loop.swift
//  RxLoop
//
//  Created by Thibault Wittemberg on 2019-02-03.
//  Copyright © 2019 WarpFactor. All rights reserved.
//
import RxSwift
import RxCocoa

public typealias StateBinder<StateType: State, A> = (Observable<StateType>) -> Observable<A>
public typealias Transformer<A, B> = (Observable<A>) -> Observable<B>
public typealias MutationEmitter<A, Mutation> = (Observable<A>) -> Observable<Mutation>
public typealias Reducer<Mutation, StateType: State> = (Observable<(Mutation, StateType)>) -> Observable<StateType>
public typealias StateInterpreter<StateType: State> = (StateType) -> Void

public class LoopRuntime<StateType: State> {
    private let loop: Observable<StateType>
    private let state: PublishRelay<StateType>
    init(with loop: Observable<StateType>, and state: PublishRelay<StateType>) {
        self.loop = loop
        self.state = state
    }

    public func start () -> Disposable {
        return self.loop.bind(to: state)
    }

    public func start<ObservableTypeType: ObservableType>(when trigger: ObservableTypeType) -> Disposable {
        return trigger.take(1).flatMap { _ -> Observable<StateType> in return self.loop }.bind(to: self.state)
    }

    public func start(after dueTime: RxTimeInterval, on scheduler: SchedulerType = MainScheduler.instance) -> Disposable {
        let trigger = Observable<Void>.just(()).delay(dueTime, scheduler: scheduler)
        return self.start(when: trigger)
    }

    public func take<ObservableTypeType: ObservableType> (until trigger: ObservableTypeType) -> LoopRuntime<StateType> {
        let loopRuntime = LoopRuntime<StateType>(with: self.loop.takeUntil(trigger.take(1)), and: self.state)
        return loopRuntime
    }
}

public func loop<Mutation, StateType: State> (stateBinder: @escaping StateBinder<StateType, Mutation>,
                                              reducer: @escaping Reducer<Mutation, StateType>) ->
    (StateType, @escaping StateInterpreter<StateType>) -> LoopRuntime<StateType> {

    func tuplize(mutations: Observable<Mutation>, states: Observable<StateType>) -> Observable<(Mutation, StateType)> {
        return mutations.withLatestFrom(states) { ($0, $1) }
    }

    return { (initialState, stateInterpreter) in
        let state = PublishRelay<StateType>()
        let initialStateObservable = state.startWith(initialState)
        let stateBinderToReducer = composeAndAggregate(f1: stateBinder, f2: tuplize)
        let stateBinderToReducedState = composeWithTwoParameters(f1: stateBinderToReducer, f2: reducer) // -> suite de fibonacci: Etat N = Etat 0 + Etat N-1
        let loop = stateBinderToReducedState(initialStateObservable, initialStateObservable).observeOn(MainScheduler.instance).do(onNext: stateInterpreter)
        return LoopRuntime(with: loop, and: state)
    }
}

public func loop<A, Mutation, StateType: State> (stateBinder: @escaping StateBinder<StateType, A>,
                                                 mutationEmitter: @escaping MutationEmitter<A, Mutation>,
                                                 reducer: @escaping Reducer<Mutation, StateType>) ->
    (StateType, @escaping StateInterpreter<StateType>) -> LoopRuntime<StateType> {

    func tuplize(mutations: Observable<Mutation>, states: Observable<StateType>) -> Observable<(Mutation, StateType)> {
        return mutations.withLatestFrom(states) { ($0, $1) }
    }

    return { (initialState, stateInterpreter) in
        let state = PublishRelay<StateType>()
        let initialStateObservable = state.startWith(initialState)
        let stateBinderToMutation = compose(f1: stateBinder, f2: mutationEmitter)
        let stateBinderToReducer = composeAndAggregate(f1: stateBinderToMutation, f2: tuplize)
        let stateBinderToReducedState = composeWithTwoParameters(f1: stateBinderToReducer, f2: reducer)
        let loop = stateBinderToReducedState(initialStateObservable, initialStateObservable).observeOn(MainScheduler.instance).do(onNext: stateInterpreter)
        return LoopRuntime(with: loop, and: state)
    }
}

public func loop<A, B, Mutation, StateType: State> (stateBinder: @escaping StateBinder<StateType, A>,
                                                    mapper: @escaping Transformer<A, B>,
                                                    mutationEmitter: @escaping MutationEmitter<B, Mutation>,
                                                    reducer: @escaping Reducer<Mutation, StateType>) ->
    (StateType, @escaping StateInterpreter<StateType>) -> LoopRuntime<StateType> {

    func tuplize(mutations: Observable<Mutation>, states: Observable<StateType>) -> Observable<(Mutation, StateType)> {
        return mutations.withLatestFrom(states) { ($0, $1) }
    }

    return { (initialState, stateInterpreter) in
        let state = PublishRelay<StateType>()
        let initialStateObservable = state.startWith(initialState)
        let stateBinderToMapper = compose(f1: stateBinder, f2: mapper)
        let stateBinderToMutation = compose(f1: stateBinderToMapper, f2: mutationEmitter)
        let stateBinderToReducer = composeAndAggregate(f1: stateBinderToMutation, f2: tuplize)
        let stateBinderToReducedState = composeWithTwoParameters(f1: stateBinderToReducer, f2: reducer)
        let loop = stateBinderToReducedState(initialStateObservable, initialStateObservable).observeOn(MainScheduler.instance).do(onNext: stateInterpreter)
        return LoopRuntime(with: loop, and: state)
    }
}
