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

public class LoopBuilder {
    public static func mutates<Mutation> (with emitter: @escaping MutationEmitter<Mutation>) -> MutationEmitterBuilder<Mutation> {
        return MutationEmitterBuilder<Mutation>(emitter: emitter)
    }
}

public class MutationEmitterBuilder<Mutation> {
    private let mutationEmitter: MutationEmitter<Mutation>

    private static func composeEmitters<A, B> (f1: @escaping () -> A, f2: @escaping (A) -> B) -> () -> B {
        return { f2(f1()) }
    }

    private static func flatten<A> (funcs: [() -> A]) -> () -> [A] {
        return { funcs.map { $0() } }
    }

    private static func mergeEmitter<A> (_ funcs: (() -> A)...) -> () -> A where A: ObservableType {

        func observableMerge(inputs: [A]) -> A {
            return Observable<A.Element>.merge(inputs.map { $0.asObservable() }) as! A
        }

        let flatFuncs = flatten(funcs: funcs)
        return MutationEmitterBuilder.composeEmitters(f1: flatFuncs, f2: observableMerge)
    }

    fileprivate init (emitter: @escaping MutationEmitter<Mutation>) {
        self.mutationEmitter = emitter
    }

    public func compose<NextMutation> (withNextMutationEmitter nextEmitter: @escaping (Observable<Mutation>) -> Observable<NextMutation>) -> MutationEmitterBuilder<NextMutation> {
        let emitter = MutationEmitterBuilder.composeEmitters(f1: self.mutationEmitter, f2: nextEmitter)
        return MutationEmitterBuilder<NextMutation>(emitter: emitter)
    }

    public func merge (withConcurrentMutationEmitter concurrentEmitter: @escaping MutationEmitter<Mutation>) -> MutationEmitterBuilder<Mutation> {
        let emitter = MutationEmitterBuilder.mergeEmitter(self.mutationEmitter, concurrentEmitter)
        return MutationEmitterBuilder<Mutation>(emitter: emitter)
    }

    public func reduces<State> (with reducer: @escaping Reducer<State, Mutation>) -> ReducerBuilder<Mutation, State> {
        return ReducerBuilder<Mutation, State>(emitter: self.mutationEmitter, reducer: reducer)
    }
}

public class ReducerBuilder<Mutation, State> {
    private let mutationEmitter: MutationEmitter<Mutation>
    private let reducer: Reducer<State, Mutation>

    fileprivate init (emitter: @escaping MutationEmitter<Mutation>, reducer: @escaping Reducer<State, Mutation>) {
        self.mutationEmitter = emitter
        self.reducer = reducer
    }

    public func interprets (with stateInterpreter: @escaping StateInterpreter<State>) -> StateInterpreterBuilder<Mutation, State> {
        return StateInterpreterBuilder<Mutation, State>(emitter: self.mutationEmitter, reducer: self.reducer, stateInterpreter: stateInterpreter)
    }

}

public class StateInterpreterBuilder<Mutation, State> {
    private let mutationEmitter: MutationEmitter<Mutation>
    private let reducer: Reducer<State, Mutation>
    private let stateInterpreter: StateInterpreter<State>

    private static func concatInterpreters<A> (_ funcs: ((A) -> Void)...) -> (A) -> Void {
        return { (a:A) in
            funcs.forEach { $0(a) }
        }
    }

    fileprivate init (emitter: @escaping MutationEmitter<Mutation>, reducer: @escaping Reducer<State, Mutation>, stateInterpreter: @escaping StateInterpreter<State>) {
        self.mutationEmitter = emitter
        self.reducer = reducer
        self.stateInterpreter = stateInterpreter
    }

    public func concat (withNextStateInterpreter nextStateInterpreter: @escaping StateInterpreter<State>) -> StateInterpreterBuilder<Mutation, State> {
        let stateInterpreters = StateInterpreterBuilder.concatInterpreters(self.stateInterpreter, nextStateInterpreter)
        return StateInterpreterBuilder<Mutation, State>(emitter: self.mutationEmitter, reducer: self.reducer, stateInterpreter: stateInterpreters)
    }

    public func interpret (on scheduler: SchedulerType) -> LoopRuntime<Mutation, State> {
        return LoopRuntime(with: self.mutationEmitter, reducer: self.reducer, interpreter: self.stateInterpreter, interpretationScheduler: scheduler)
    }
}

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

    @discardableResult public func start(with initialState: State) -> Disposable {
        return self
            .startStateObservable(with: initialState)
            .subscribe()
    }

    @discardableResult public func start<ObservableTypeType: ObservableType>(with initialState: State, when trigger: ObservableTypeType) -> Disposable {
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

//public func loop<Mutation, State> (mutationEmitter: @escaping MutationEmitter<Mutation>,
//                                   reducer: @escaping Reducer<State, Mutation>,
//                                   interpreter: @escaping StateInterpreter<State>,
//                                   interpretationScheduler: SchedulerType = MainScheduler.instance) -> LoopRuntime<Mutation, State> {
//    return LoopRuntime(with: mutationEmitter,
//                       reducer: reducer,
//                       interpreter: interpreter,
//                       interpretationScheduler: interpretationScheduler)
//}
