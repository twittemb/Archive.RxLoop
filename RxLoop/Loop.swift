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

public class LoopRuntime<Mutation, State> {
    private let mutationEmitter: MutationEmitter<Mutation>
    private let reducer: Reducer<State, Mutation>
    private let interpreter: StateInterpreter<State>
    private let interpretationScheduler: SchedulerType

    fileprivate init (with mutationEmitter: @escaping MutationEmitter<Mutation>,
                      reducer: @escaping Reducer<State, Mutation>,
                      interpreter: @escaping StateInterpreter<State>,
                      interpretationScheduler: SchedulerType = MainScheduler.instance) {
        self.mutationEmitter = mutationEmitter
        self.reducer = reducer
        self.interpreter = interpreter
        self.interpretationScheduler = interpretationScheduler
    }

    private func startStateObservable (with initialState: State) -> Observable<State> {
        return self.mutationEmitter()
            .scan(initialState, accumulator: self.reducer)
            .observeOn(self.interpretationScheduler)
            .do(onNext: self.interpreter)
    }

    public func start(with initialState: State) -> Disposable {
        return self
            .startStateObservable(with: initialState)
            .subscribe()
    }

    public func start<ObservableTypeType: ObservableType>(with initialState: State, when trigger: ObservableTypeType) -> Disposable {
        return trigger
            .take(1)
            .observeOn(self.interpretationScheduler)
            .do(onNext: { _ in self.interpreter(initialState) })
            .flatMap { _ -> Observable<State> in
                return self.startStateObservable(with: initialState)
            }
            .subscribe()
    }

    public func take<ObservableTypeType: ObservableType> (until trigger: ObservableTypeType) -> LoopRuntime<Mutation, State> {
        func untilLoop() -> Observable<Mutation> {
            return self.mutationEmitter().takeUntil(trigger)
        }

        return LoopRuntime<Mutation, State>(with: untilLoop,
                                            reducer: self.reducer,
                                            interpreter: self.interpreter,
                                            interpretationScheduler: self.interpretationScheduler)
    }
}

public func loop<Mutation, State> (mutationEmitter: @escaping MutationEmitter<Mutation>,
                                   reducer: @escaping Reducer<State, Mutation>,
                                   interpreter: @escaping StateInterpreter<State>,
                                   interpretationScheduler: SchedulerType = MainScheduler.instance) -> LoopRuntime<Mutation, State> {
    return LoopRuntime(with: mutationEmitter,
                       reducer: reducer,
                       interpreter: interpreter,
                       interpretationScheduler: interpretationScheduler)
}
