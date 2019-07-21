//
//  LoopCombine.swift
//  RxLoop
//
//  Created by Thibault Wittemberg on 2019-06-24.
//  Copyright © 2019 WarpFactor. All rights reserved.
//
import Combine

public typealias MutationEmitter<Mutation> = () -> AnyPublisher<Mutation, Never>
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

    private static func mergeEmitter<A> (_ funcs: (() -> A)...) -> () -> A where A: Publisher {

        func observableMerge(inputs: [A]) -> A {
            return Publishers.MergeMany(inputs).eraseToAnyPublisher() as! A
        }

        let flatFuncs = MutationEmitterBuilder.flatten(funcs: funcs)
        return MutationEmitterBuilder.composeEmitters(f1: flatFuncs, f2: observableMerge)
    }

    fileprivate init (emitter: @escaping MutationEmitter<Mutation>) {
        self.mutationEmitter = emitter
    }

    public func compose<NextMutation> (withNextMutationEmitter nextEmitter: @escaping (AnyPublisher<Mutation, Never>) -> AnyPublisher<NextMutation, Never>) -> MutationEmitterBuilder<NextMutation> {
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

    public func interpret (on queue: DispatchQueue) -> LoopRuntime<Mutation, State> {
        return LoopRuntime(with: self.mutationEmitter, reducer: self.reducer, interpreter: self.stateInterpreter, interpretationQueue: queue)
    }
}

public class LoopRuntime<Mutation, State> {
    private let mutationEmitter: MutationEmitter<Mutation>
    private let reducer: Reducer<State, Mutation>
    private let interpreter: StateInterpreter<State>
    private let interpretationQueue: DispatchQueue
    
    init (with mutationEmitter: @escaping MutationEmitter<Mutation>,
          reducer: @escaping Reducer<State, Mutation>,
          interpreter: @escaping StateInterpreter<State>,
          interpretationQueue: DispatchQueue = .main) {
        self.mutationEmitter = mutationEmitter
        self.reducer = reducer
        self.interpreter = interpreter
        self.interpretationQueue = interpretationQueue
    }
    
    private func startStatePublisher (with initialState: State) -> AnyPublisher<State, Never> {
        return self.mutationEmitter()
            .scan(initialState, self.reducer)
            .receive(on: self.interpretationQueue)
            .handleEvents(receiveOutput: { state in self.interpreter(state) })
            .eraseToAnyPublisher()
    }
    
    public func start(with initialState: State) -> AnyCancellable {
        return self.startStatePublisher(with: initialState).subscribe(PassthroughSubject<State, Never>())
    }
    
    public func start<PublisherType: Publisher>(with initialState: State, when trigger: PublisherType) -> AnyCancellable where PublisherType.Failure == Never {
        return trigger
            .first()
            .receive(on: self.interpretationQueue)
            .handleEvents(receiveOutput: { _ in self.interpreter(initialState) })
            .flatMap { _ -> AnyPublisher<State, Never> in
                return self.startStatePublisher(with: initialState)
        }
        .subscribe(PassthroughSubject<State, Never>())
    }
    
    public func take<PublisherType: Publisher> (until trigger: PublisherType) -> LoopRuntime<Mutation, State> where PublisherType.Failure == Never {
        func untilLoop() -> AnyPublisher<Mutation, Never> {
            return self.mutationEmitter().prefix(untilOutputFrom: trigger).eraseToAnyPublisher()
        }
        
        return LoopRuntime<Mutation, State>(with: untilLoop,
                                            reducer: self.reducer,
                                            interpreter: self.interpreter,
                                            interpretationQueue: self.interpretationQueue)
    }
}

//public func loopCombine<Mutation, State> (mutationEmitter: @escaping MutationEmitterCombine<Mutation>,
//                                          reducer: @escaping ReducerCombine<State, Mutation>,
//                                          interpreter: @escaping StateInterpreterCombine<State>,
//                                          interpretationQueue: DispatchQueue = .main) -> LoopRuntime<Mutation, State> {
//    return LoopRuntime(with: mutationEmitter,
//                       reducer: reducer,
//                       interpreter: interpreter,
//                       interpretationQueue: interpretationQueue)
//}
