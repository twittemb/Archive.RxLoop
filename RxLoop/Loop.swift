//
//  Loop.swift
//  RxLoop
//
//  Created by Thibault Wittemberg on 2019-02-03.
//  Copyright © 2019 WarpFactor. All rights reserved.
//
import RxSwift
import RxCocoa

public typealias MutationEmitter<Mutation> = () -> Observable<Mutation>
public typealias Reducer<State, Mutation> = (State, Mutation) -> State
public typealias StateInterpreter<State> = (State) -> Void
public typealias Loop<State> = (Observable<State>) -> Observable<State>

public class LoopRuntime<State> {
    private var loop: Loop<State>
    private let state = PublishRelay<State>()
    private let interpreter: StateInterpreter<State>
    
    init(with loop: @escaping Loop<State>, interpreter: @escaping StateInterpreter<State>) {
        self.loop = loop
        self.interpreter = interpreter
    }

    public func start (with initialState: State) -> Disposable {
        let initialStateObservable = state.startWith(initialState)
        return self.loop(initialStateObservable).observeOn(MainScheduler.instance).do(onNext: self.interpreter).bind(to: self.state)
    }

    public func start<ObservableTypeType: ObservableType>(with initialState: State, when trigger: ObservableTypeType) -> Disposable {
        let initialStateObservable = state.startWith(initialState)
        return trigger.take(1).flatMap { _ -> Observable<State> in return self.loop(initialStateObservable) }.bind(to: self.state)
    }

    public func start(with initialState: State, after dueTime: RxTimeInterval, on scheduler: SchedulerType = MainScheduler.instance) -> Disposable {
        let trigger = Observable<Void>.just(()).delay(dueTime, scheduler: scheduler)
        return self.start(with: initialState, when: trigger)
    }

    public func take<ObservableTypeType: ObservableType> (until trigger: ObservableTypeType) -> LoopRuntime<State> {
        func untilLoop(state: Observable<State>) -> Observable<State> {
            return self.loop(state).takeUntil(trigger)
        }

        return LoopRuntime<State>(with: untilLoop, interpreter: self.interpreter)
    }
}


public func loop<Mutation, State> (mutationEmitter: @escaping MutationEmitter<Mutation>,
                                   reducer: @escaping Reducer<State, Mutation>,
                                   interpreter: @escaping StateInterpreter<State>) -> LoopRuntime<State> {

    func tuplize(states: Observable<State>, mutations: Observable<Mutation>) -> Observable<(State, Mutation)> {
        return mutations.withLatestFrom(states) { ($1, $0) }
    }

    func makeObservable<State, Mutation> (f: @escaping (State, Mutation) -> State) -> (Observable<(State, Mutation)>) -> Observable<State>  {
        return { (observable: Observable<(State, Mutation)>) -> Observable<State> in
            return observable.map(f)
        }
    }

    //        let state = PublishRelay<StateType>()
    //        let initialStateObservable = state.startWith(initialState)
    let stateBinderToReducer = composeAndAggregate(f1: mutationEmitter, f2: tuplize)
    let observableReducer = makeObservable(f: reducer)
    let stateBinderToReducedState = compose1(f1: stateBinderToReducer, f2: observableReducer) // -> suite de fibonacci: Etat N = Etat 0 + Etat N-1
    // should return the stateBinderToReducedState as a result to be able to feed the stateInterpreter when starting the LoopRuntime
//    let loop = stateBinderToReducedState(initialStateObservable).observeOn(MainScheduler.instance).do(onNext: stateInterpreter)
    return LoopRuntime(with: stateBinderToReducedState, interpreter: interpreter)
}
