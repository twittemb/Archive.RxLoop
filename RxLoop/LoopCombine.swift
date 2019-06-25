//
//  LoopCombine.swift
//  RxLoop
//
//  Created by Thibault Wittemberg on 2019-06-24.
//  Copyright © 2019 WarpFactor. All rights reserved.
//
import Combine

public typealias MutationEmitterCombine<Mutation> = () -> AnyPublisher<Mutation, Never>
public typealias ReducerCombine<State, Mutation> = (State, Mutation) -> State
public typealias StateInterpreterCombine<State> = (State) -> Void

public class LoopRuntimeCombine<Mutation, State> {
    private let mutationEmitter: MutationEmitterCombine<Mutation>
    private let reducer: ReducerCombine<State, Mutation>
    private let interpreter: StateInterpreterCombine<State>
    private let interpretationQueue: DispatchQueue
    
    init (with mutationEmitter: @escaping MutationEmitterCombine<Mutation>,
          reducer: @escaping ReducerCombine<State, Mutation>,
          interpreter: @escaping StateInterpreterCombine<State>,
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
    
    public func take<PublisherType: Publisher> (until trigger: PublisherType) -> LoopRuntimeCombine<Mutation, State> where PublisherType.Failure == Never {
        func untilLoop() -> AnyPublisher<Mutation, Never> {
            return self.mutationEmitter().prefix(untilOutputFrom: trigger).eraseToAnyPublisher()
        }
        
        return LoopRuntimeCombine<Mutation, State>(with: untilLoop,
                                                   reducer: self.reducer,
                                                   interpreter: self.interpreter,
                                                   interpretationQueue: self.interpretationQueue)
    }
}

public func loopCombine<Mutation, State> (mutationEmitter: @escaping MutationEmitterCombine<Mutation>,
                                          reducer: @escaping ReducerCombine<State, Mutation>,
                                          interpreter: @escaping StateInterpreterCombine<State>,
                                          interpretationQueue: DispatchQueue = .main) -> LoopRuntimeCombine<Mutation, State> {
    return LoopRuntimeCombine(with: mutationEmitter,
                              reducer: reducer,
                              interpreter: interpreter,
                              interpretationQueue: interpretationQueue)
}
