#if canImport(Foundation)
@attached(member, names: arbitrary)
public macro Request() = #externalMacro(module: "NetworkingMacros", type: "RequestMacro")

@attached(member, names: arbitrary)
public macro Client() = #externalMacro(module: "NetworkingMacros", type: "ClientMacro")

@attached(peer, names: arbitrary)
public macro Parameter() = #externalMacro(module: "NetworkingMacros", type: "ParameterMacro")
#endif
