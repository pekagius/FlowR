using System;
using System.Collections.Generic;
using System.Linq;
using FlowR.Pipeline;
using Microsoft.Extensions.DependencyInjection;
using Shouldly;
using Xunit;

namespace FlowR.Tests.MicrosoftExtensionsDI;

public class TypeEvaluatorTests
{
    private readonly IServiceProvider _provider;
    private readonly IServiceCollection _services;
    private readonly Logger _logger = new Logger();

    // Generiere Dummy-Klassen in Included-Namespace für die Tests
    private class IncludedFoo : IRequest<Bar> { }
    private class IncludedFooHandler : IRequestHandler<IncludedFoo, Bar>
    {
        public System.Threading.Tasks.Task<Bar> Handle(IncludedFoo request, System.Threading.CancellationToken cancellationToken)
        {
            return System.Threading.Tasks.Task.FromResult(new Bar());
        }
    }

    public TypeEvaluatorTests()
    {
        _services = new ServiceCollection();
        _services.AddSingleton(_logger);
        _services.AddFlowR(cfg =>
        {
            cfg.RegisterServicesFromAssemblyContaining(typeof(Ping));
            // Reduzieren wir den Test auf den aktuellen Namespace und die eingeschlossenen Handler
            cfg.TypeFilter = t => t == typeof(IncludedFooHandler) || t == typeof(FooHandler);
        });
        _services.AddSingleton<INotificationPublisher, NotificationPublishers.ForeachAwaitPublisher>();
        _provider = _services.BuildServiceProvider();
    }

    [Fact]
    public void ShouldResolveMediator()
    {
        ShouldBeNullExtensions.ShouldNotBeNull(_provider.GetService<IMediator>());
    }

    [Fact]
    public void ShouldOnlyResolveIncludedRequestHandlers()
    {
        ShouldBeNullExtensions.ShouldNotBeNull(_provider.GetService<IRequestHandler<IncludedFoo, Bar>>());
        ShouldBeNullExtensions.ShouldBeNull(_provider.GetService<IRequestHandler<Ping, Pong>>());
    }

    [Fact(Skip = "Dies wird übersprungen, da die Behaviors jetzt standardmäßig hinzugefügt werden")]
    public void ShouldNotRegisterUnNeededBehaviors()
    {
        _services.Any(service => service.ImplementationType == typeof(RequestPreProcessorBehavior<,>))
            .ShouldBeFalse();
        _services.Any(service => service.ImplementationType == typeof(RequestPostProcessorBehavior<,>))
            .ShouldBeFalse();
        _services.Any(service => service.ImplementationType == typeof(RequestExceptionActionProcessorBehavior<,>))
            .ShouldBeFalse();
        _services.Any(service => service.ImplementationType == typeof(RequestExceptionProcessorBehavior<,>))
            .ShouldBeFalse();
    }
}

public class TypeLogger
{
    public IList<string> Messages { get; } = new List<string>();
}