# FlowR

![Build Status](https://github.com/pekagi/FlowR/workflows/CI/badge.svg)
[![NuGet](https://img.shields.io/nuget/dt/flowr.svg)](https://www.nuget.org/packages/flowr) 
[![NuGet](https://img.shields.io/nuget/vpre/flowr.svg)](https://www.nuget.org/packages/flowr)

## About FlowR

FlowR is an open-source continuation of the MediatR library, which became commercial starting with version 13. This fork aims to maintain the simplicity and power of the original while ensuring it remains freely available to the community.

FlowR is an elegant and powerful mediator implementation for .NET with a focus on workflow automation. Unlike other frameworks, FlowR relies on clear communication patterns and seamlessly supports both simple and complex use cases.

The library enables:
- Clean separation of request and processing (CQRS pattern)
- Implementation of complex workflows through chained requests
- Easy extensibility through pipeline behaviors
- Support for synchronous and asynchronous code
- Full compatibility with legacy MediatR projects

## Installation

FlowR can be easily installed via NuGet:

```
Install-Package FlowR
```

Or via the .NET Core command line:

```
dotnet add package FlowR
```

## Using Only the Contracts

To use only the contract classes and interfaces (useful when you only need definitions in a separate assembly):

```
Install-Package FlowR.Contracts
```

This includes:
- `IRequest` (including generic variants)
- `INotification`
- `IStreamRequest`

## Registration with `IServiceCollection`

FlowR supports direct integration with `Microsoft.Extensions.DependencyInjection.Abstractions`:

```csharp
services.AddFlowR(cfg => cfg.RegisterServicesFromAssemblyContaining<Startup>());
```

Or with an assembly:

```csharp
services.AddFlowR(cfg => cfg.RegisterServicesFromAssembly(typeof(Startup).Assembly));
```

## Core Concepts

### Requests

Requests are objects that represent a requirement and expect a response:

```csharp
public record GetUserQuery(int UserId) : IRequest<UserDto>;

public class GetUserQueryHandler : IRequestHandler<GetUserQuery, UserDto>
{
    public async Task<UserDto> Handle(GetUserQuery request, CancellationToken cancellationToken)
    {
        // Implementation to retrieve a user
    }
}
```

### Notifications

Notifications allow publishing events to multiple handlers:

```csharp
public record UserCreatedNotification(int UserId, string Username) : INotification;

public class EmailNotificationHandler : INotificationHandler<UserCreatedNotification>
{
    public async Task Handle(UserCreatedNotification notification, CancellationToken cancellationToken)
    {
        // Send a welcome email
    }
}
```

### Pipeline Behavior

FlowR allows inserting custom behaviors into the request pipeline:

```csharp
public class LoggingBehavior<TRequest, TResponse> : IPipelineBehavior<TRequest, TResponse>
    where TRequest : IRequest<TResponse>
{
    public async Task<TResponse> Handle(TRequest request, RequestHandlerDelegate<TResponse> next, CancellationToken cancellationToken)
    {
        // Log before processing
        var response = await next();
        // Log after processing
        return response;
    }
}
```

## Compatibility with MediatR

FlowR provides full compatibility with MediatR through type forwarding and interface aliases. This enables seamless migration from existing MediatR projects to FlowR.

## License

FlowR is available under the Apache 2.0 license. See LICENSE for details.
