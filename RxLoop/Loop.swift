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
    private let interpretationScheduler: SchedulerType
    
    fileprivate init(with loop: @escaping Loop<State>, interpreter: @escaping StateInterpreter<State>, interpretationScheduler: SchedulerType) {
        self.loop = loop
        self.interpreter = interpreter
        self.interpretationScheduler = interpretationScheduler
    }

    public func start (with initialState: State) -> Disposable {
        let initialStateObservable = state.startWith(initialState)
        return self.loop(initialStateObservable).observeOn(interpretationScheduler).do(onNext: self.interpreter).bind(to: self.state)
    }

    public func start<ObservableTypeType: ObservableType>(with initialState: State, when trigger: ObservableTypeType) -> Disposable {
        let initialStateObservable = state.startWith(initialState)
        return trigger.take(1)
            .observeOn(interpretationScheduler)
            .do(onNext: { _ in
                self.interpreter(initialState)
            })
            .flatMap { _ -> Observable<State> in
                return self
                    .loop(initialStateObservable)
                    .observeOn(self.interpretationScheduler)
                    .do(onNext: self.interpreter)
            }
            .bind(to: self.state)
    }

    public func start(with initialState: State, after dueTime: RxTimeInterval, on scheduler: SchedulerType = MainScheduler.instance) -> Disposable {
        let trigger = Observable<Void>.just(()).delay(dueTime, scheduler: scheduler)
        return self.start(with: initialState, when: trigger)
    }

    public func take<ObservableTypeType: ObservableType> (until trigger: ObservableTypeType) -> LoopRuntime<State> {
        func untilLoop(state: Observable<State>) -> Observable<State> {
            return self.loop(state).takeUntil(trigger)
        }

        return LoopRuntime<State>(with: untilLoop, interpreter: self.interpreter, interpretationScheduler: self.interpretationScheduler)
    }
}


public func loop<Mutation, State> (mutationEmitter: @escaping MutationEmitter<Mutation>,
                                   reducer: @escaping Reducer<State, Mutation>,
                                   interpreter: @escaping StateInterpreter<State>,
                                   interpretationScheduler: SchedulerType = MainScheduler.instance) -> LoopRuntime<State> {

    func tuplize(states: Observable<State>, mutations: Observable<Mutation>) -> Observable<(State, Mutation)> {
        return mutations.withLatestFrom(states) { ($1, $0) }
    }

    func makeObservable<State, Mutation> (f: @escaping (State, Mutation) -> State) -> (Observable<(State, Mutation)>) -> Observable<State>  {
        return { (observable: Observable<(State, Mutation)>) -> Observable<State> in
            return observable.map(f)
        }
    }

    let stateBinderToReducer = composeAndAggregate(f1: mutationEmitter, f2: tuplize)
    let observableReducer = makeObservable(f: reducer)
    let stateBinderToReducedState = compose1(f1: stateBinderToReducer, f2: observableReducer)
    return LoopRuntime(with: stateBinderToReducedState, interpreter: interpreter, interpretationScheduler: interpretationScheduler)
}
