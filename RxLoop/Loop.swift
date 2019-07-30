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
    public static func from<Mutation> (_ mutationEmitter: @escaping MutationEmitter<Mutation>) -> MutationEmitterBuilder<Mutation> {
        return MutationEmitterBuilder<Mutation>(emitter: mutationEmitter)
    }
}

public class MutationEmitterBuilder<Mutation> {
    fileprivate let mutationEmitter: MutationEmitter<Mutation>

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

    public func compose<NextMutation> (with nextEmitter: @escaping (Observable<Mutation>) -> Observable<NextMutation>) -> MutationEmitterBuilder<NextMutation> {
        let emitter = MutationEmitterBuilder.composeEmitters(f1: self.mutationEmitter, f2: nextEmitter)
        return MutationEmitterBuilder<NextMutation>(emitter: emitter)
    }

    public func merge (with concurrentEmitter: @escaping MutationEmitter<Mutation>) -> MutationEmitterBuilder<Mutation> {
        let emitter = MutationEmitterBuilder.mergeEmitter(self.mutationEmitter, concurrentEmitter)
        return MutationEmitterBuilder<Mutation>(emitter: emitter)
    }

    public func scan<State> (initialState: State, with reducer: @escaping Reducer<State, Mutation>) -> ReducerBuilder<Mutation, State> {
        return ReducerBuilder<Mutation, State>(mutationEmitterBuilder: self, initialState: initialState, reducer: reducer)
    }
}

public class ReducerBuilder<Mutation, State> {
    fileprivate let mutationEmitterBuilder: MutationEmitterBuilder<Mutation>
    fileprivate let initialState: State
    fileprivate let reducer: Reducer<State, Mutation>

    fileprivate init (mutationEmitterBuilder: MutationEmitterBuilder<Mutation>, initialState: State, reducer: @escaping Reducer<State, Mutation>) {
        self.mutationEmitterBuilder = mutationEmitterBuilder
        self.initialState = initialState
        self.reducer = reducer
    }

    public func consume (by stateInterpreter: @escaping StateInterpreter<State>,
                         on scheduler: SchedulerType = MainScheduler.instance) -> StateInterpreterBuilder<Mutation, State> {
        return StateInterpreterBuilder<Mutation, State>(reducerBuilder: self,
                                                        stateInterpreter: stateInterpreter,
                                                        stateInterpreterScheduler: scheduler)
    }
}

public class StateInterpreterBuilder<Mutation, State> {
    private let reducerBuilder: ReducerBuilder<Mutation, State>
    private let stateInterpreter: StateInterpreter<State>
    private let stateInterpreterScheduler: SchedulerType

    private static func concatInterpreters<A> (_ funcs: ((A) -> Void)...) -> (A) -> Void {
        return { (a:A) in
            funcs.forEach { $0(a) }
        }
    }

    fileprivate init (reducerBuilder: ReducerBuilder<Mutation, State>,
                      stateInterpreter: @escaping StateInterpreter<State>,
                      stateInterpreterScheduler: SchedulerType) {
        self.reducerBuilder = reducerBuilder
        self.stateInterpreter = stateInterpreter
        self.stateInterpreterScheduler = stateInterpreterScheduler
    }

    public func concat (withNextStateInterpreter nextStateInterpreter: @escaping StateInterpreter<State>) -> StateInterpreterBuilder<Mutation, State> {
        let stateInterpreters = StateInterpreterBuilder.concatInterpreters(self.stateInterpreter, nextStateInterpreter)
        return StateInterpreterBuilder<Mutation, State>(reducerBuilder: self.reducerBuilder,
                                                        stateInterpreter: stateInterpreters,
                                                        stateInterpreterScheduler: self.stateInterpreterScheduler)
    }

    public func build() -> Disposable {
        return self.reducerBuilder.mutationEmitterBuilder.mutationEmitter()
            .scan(self.reducerBuilder.initialState, accumulator: self.reducerBuilder.reducer)
            .startWith(self.reducerBuilder.initialState)
            .observeOn(self.stateInterpreterScheduler)
            .do(onNext: self.stateInterpreter)
            .subscribe()
    }
}
