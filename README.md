# FlowR
<hr>

## About FlowR

FlowR is an open-source continuation of the MediatR library, which will become commercial starting with version 13. This fork aims to maintain the simplicity and power of the original while ensuring it remains freely available to the community.

FlowR is an elegant and powerful mediator implementation for .NET with a focus on workflow automation. Unlike other frameworks, FlowR relies on clear communication patterns and seamlessly supports both simple and complex use cases.

The library enables:
- Clean separation of request and processing (CQRS pattern)
- Implementation of complex workflows through chained requests
- Easy extensibility through pipeline behaviors
- Support for synchronous and asynchronous code
- Full compatibility with legacy MediatR projects

## Installation (coming soon)

FlowR can be easily installed via NuGet:

```
Install-Package FlowR
```

Or via the .NET Core command line:

```
dotnet add package FlowR
```

## Using Only the Contracts (coming soon)

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

## Performance Optimization with Source Generation

FlowR now offers an option for performance optimization through source generation. This avoids costly reflection and assembly scans at runtime by generating the code for handler registration during the build process.

### Using Source Generation

To activate source generation, use the `UseSourceGeneration()` extension method in your configuration:

```csharp
services.AddFlowR(config => 
{
    config.RegisterServicesFromAssemblyContaining<Startup>()
          .UseSourceGeneration(); // Activates source generation
});
```

### How It Works

Instead of scanning all assemblies at runtime, which is resource-intensive, the FlowR Source Generator generates a static registration class at compile time. This contains all information about handlers, notifications, and other FlowR components that can then be registered directly without reflection.

1. During the build, the source generator analyzes your code
2. It detects all handlers, notifications, and other FlowR components
3. It generates a special registration class that knows about these components
4. At runtime, this generated class is used instead of assembly scanning

### Benefits of Source Generation

- **Significantly improved startup performance**: No costly reflection and assembly scans at runtime
- **Early error detection**: Issues with handlers are detected at compile time
- **Optimized handler registration**: Direct registration of handlers without dynamic type searching
- **Reduced memory usage**: Fewer temporary objects during initialization
- **Better scalability**: The startup time doesn't grow with the number of handlers

### When to Use Source Generation

Source generation is particularly useful for:

- Applications with many handlers and notifications
- Services where startup time is critical
- Serverless functions that need to start quickly
- Containerized applications where fast startup is important

For small applications or during development, traditional assembly scanning might be more practical since it doesn't require recompilation when new handlers are added.

## License

FlowR is available under the Apache 2.0 license. See LICENSE for details.
Hint: FlowR will stay free to use
