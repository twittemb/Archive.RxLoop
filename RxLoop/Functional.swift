//
//  Functional.swift
//  RxLoop
//
//  Created by Thibault Wittemberg on 2019-03-07.
//  Copyright © 2019 WarpFactor. All rights reserved.
//

import RxSwift

/// Compose 2 functions into a third one having the input type
/// of the first function and the output type of the second one.
/// 
/// example:
/// ```
/// func square (a: Int) -> Int { return a*a }
/// func stringify (a: Int) -> String { return "\(a)" }
///
/// let composedFunc = compose(f1: square, f2: stringify)
///
/// will be a function of type: (Int) -> String
/// and composedFunc(3) will result in the String "9"
/// ```
///
/// - Parameters:
///     - f1: The first function which output type has to be the same as the second function input type
///     - f2: The second function
/// - Returns: A third function having the input type of the first function and the output type of the second one
func compose<A, B, C> (f1: @escaping (A) -> B, f2: @escaping (B) -> C) -> (A) -> C {
    return { a in f2(f1(a)) }
}

/// Compose 2 functions into a third one having 2 input types: the input type of the first function, the second input type of the second function
/// The output type of the composed function it the same as the output
/// type of the second function.
///
/// example:
/// ```
/// func divideBy2 (a: Int) -> Double { return a/2 }
/// func stringify (a: Double, b: Bool) -> String { return "\(a), \(b)" }
///
/// let composedFunc = compose(f1: divideBy2, f2: stringify)
///
/// will be a function of type: (Int, Bool) -> String
/// and composedFunc(3, true) will result in the String "1.5, true"
/// ```
///
/// The idea is to `agregate` the two distinct parameters of the 2 functions,
/// by masking the type they have in common: the output of the first function
/// and the first input of the second one.
///
/// - Parameters:
///     - f1: The first function which output type has to be the same as the second function first input type
///     - f2: The second function
/// - Returns: A third function having the input types of the first and second functions and the output type of the second one
func composeAndAggregate<A, B, C, D> (f1: @escaping (A) -> B, f2: @escaping (B, C) -> D) -> (A, C) -> D {
    return { (a, c) in f2(f1(a), c) }
}

/// Compose 2 functions into a third one having the two input types
/// of the first function and the output type of the second one.
///
/// example:
/// ```
/// func multiply (a: Int, b: Double) -> Double { return a*b }
/// func stringify (a: Double) -> String { return "\(a)" }
///
/// let composedFunc = compose(f1: multiply, f2: stringify)
///
/// will be a function of type: (Int, Double) -> String
/// and composedFunc(3, 4.0) will result in the String "12.0"
/// ```
///
/// - Parameters:
///     - f1: The first function which output type has to be the same as the second function input type
///     - f2: The second function
/// - Returns: A function having the two input types of the first function and the output type of the second one.
func composeWithTwoParameters<A, B, C, D> (f1: @escaping (A, B) -> C, f2: @escaping (C) -> D) -> (A, B) -> D {
    return { (a, b) in f2(f1(a, b)) }
}

/// Transform an array of functions having the same signature into a function having the input type
/// of the individual functions and having an output type being an array of output types of the individual function.
///
/// example:
/// ```
/// func square (a: Int) -> Int { return a*a }
/// func addOne (a: Int) -> Int { return a+1 }
/// func multiplyByTwo (a: Int) -> Int { return a*2 }
///
///
/// let composedFunc = flatten(funcs: [square, addOne, multiplyByTwo]])
///
/// will be a function of type: (Int) -> [Int]
/// and composedFunc(2) will result in the Array [4, 3, 4]
/// ```
///
/// - Parameter funcs: The array of functions to flatten
/// - Returns: A function applying each individual function on the input
func flatten<A, B> (funcs: [(A) -> B]) -> (A) -> [B] {
    return { a in funcs.map { $0(a) } }
}

public func merge<A, B> (_ funcs: ((A) -> B)...) -> (A) -> B where A: ObservableType, B: ObservableType {

    func observableMerge(inputs: [B]) -> B {
        return Observable<B.E>.merge(inputs.map { $0.asObservable() }) as! B
    }


    let flatFuncs = flatten(funcs: funcs)
    return compose(f1: flatFuncs, f2: observableMerge)
}

public func concat<A> (_ funcs: ((A) -> Void)...) -> (A) -> Void {
    return { (a:A) in
        funcs.forEach { $0(a) }
    }
}
