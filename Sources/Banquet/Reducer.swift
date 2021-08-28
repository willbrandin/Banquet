import Foundation
import Combine
import os.log

public struct Reducer<State, Action, Environment> {
    public let reduce: (inout State, Action, Environment) -> AnyPublisher<Action, Never>

    public init(reduce: @escaping (inout State, Action, Environment) -> AnyPublisher<Action, Never>) {
        self.reduce = reduce
    }
    
    public func callAsFunction(_ state: inout State, _ action: Action, _ environment: Environment) -> AnyPublisher<Action, Never> {
        reduce(&state, action, environment)
    }

    public func indexed<LiftedState, LiftedAction, LiftedEnvironment, Key>(
        keyPath: WritableKeyPath<LiftedState, [Key: State]>,
        extractAction: @escaping (LiftedAction) -> (Key, Action)?,
        embedAction: @escaping (Key, Action) -> LiftedAction,
        extractEnvironment: @escaping (LiftedEnvironment) -> Environment
    ) -> Reducer<LiftedState, LiftedAction, LiftedEnvironment> {
        .init { state, action, environment in
            guard let (index, action) = extractAction(action) else {
                return Empty(completeImmediately: true).eraseToAnyPublisher()
            }
            let environment = extractEnvironment(environment)
            return self.optional()
                .reduce(&state[keyPath: keyPath][index], action, environment)
                .map { embedAction(index, $0) }
                .eraseToAnyPublisher()
        }
    }

    public func indexed<LiftedState, LiftedAction, LiftedEnvironment>(
        keyPath: WritableKeyPath<LiftedState, [State]>,
        extractAction: @escaping (LiftedAction) -> (Int, Action)?,
        embedAction: @escaping (Int, Action) -> LiftedAction,
        extractEnvironment: @escaping (LiftedEnvironment) -> Environment
    ) -> Reducer<LiftedState, LiftedAction, LiftedEnvironment> {
        .init { state, action, environment in
            guard let (index, action) = extractAction(action) else {
                return Empty(completeImmediately: true).eraseToAnyPublisher()
            }
            let environment = extractEnvironment(environment)
            return self.reduce(&state[keyPath: keyPath][index], action, environment)
                .map { embedAction(index, $0) }
                .eraseToAnyPublisher()
        }
    }

    public func optional() -> Reducer<State?, Action, Environment> {
        .init { state, action, environment in
            if state != nil {
                return self(&state!, action, environment)
            } else {
                return Empty(completeImmediately: true).eraseToAnyPublisher()
            }
        }
    }

    public func lift<LiftedState, LiftedAction, LiftedEnvironment>(
        keyPath: WritableKeyPath<LiftedState, State>,
        extractAction: @escaping (LiftedAction) -> Action?,
        embedAction: @escaping (Action) -> LiftedAction,
        extractEnvironment: @escaping (LiftedEnvironment) -> Environment
    ) -> Reducer<LiftedState, LiftedAction, LiftedEnvironment> {
        .init { state, action, environment in
            let environment = extractEnvironment(environment)
            guard let action = extractAction(action) else {
                return Empty(completeImmediately: true).eraseToAnyPublisher()
            }
            let effect = self(&state[keyPath: keyPath], action, environment)
            return effect.map(embedAction).eraseToAnyPublisher()
        }
    }

    public static func combine(_ reducers: Reducer...) -> Reducer {
        .init { state, action, environment in
            let effects = reducers.compactMap { $0(&state, action, environment) }
            return Publishers.MergeMany(effects).eraseToAnyPublisher()
        }
    }
}

public extension Reducer where Action: Equatable {
    
    func logWithoutActions(actions: [Action], log: OSLog = OSLog(subsystem: "com.aaplab.food", category: "Reducer")) -> Reducer {
        .init { state, action, environment in
            if !actions.contains(action) {
                os_log(.default, log: log, "Action %s", String(reflecting: action))
            }

            let effect = self.reduce(&state, action, environment)
            
            if !actions.contains(action) {
                os_log(.default, log: log, "State %s", String(reflecting: state))
            }
            
            return effect
        }
    }
}

public extension Reducer {
    func signpost(log: OSLog = OSLog(subsystem: "com.aaplab.food", category: "Reducer")) -> Reducer {
        .init { state, action, environment in
            os_signpost(.begin, log: log, name: "Action", "%s", String(reflecting: action))
            let effect = self.reduce(&state, action, environment)
            os_signpost(.end, log: log, name: "Action", "%s", String(reflecting: action))
            return effect
        }
    }
    
    func log(log: OSLog = OSLog(subsystem: "com.aaplab.food", category: "Reducer")) -> Reducer {
        .init { state, action, environment in
            os_log(.default, log: log, "Action %s", String(reflecting: action))
            let effect = self.reduce(&state, action, environment)
            os_log(.default, log: log, "State %s", String(reflecting: state))
            return effect
        }
    }
}

public extension Publisher {
    static var none: AnyPublisher<Self.Output, Self.Failure> {
        return Empty(completeImmediately: true).eraseToAnyPublisher()
    }
}
