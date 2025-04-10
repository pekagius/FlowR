using System;
using System.Linq;
using Microsoft.Extensions.DependencyInjection;
using Shouldly;
using Xunit;

namespace FlowR.Tests.MicrosoftExtensionsDI;

public class AssemblyResolutionTests
{
    private readonly IServiceProvider _provider;

    public AssemblyResolutionTests()
    {
        IServiceCollection services = new ServiceCollection();
        services.AddSingleton(new Logger());
        services.AddFlowR(cfg =>
        {
            cfg.RegisterServicesFromAssembly(typeof(Ping).Assembly);
            cfg.RegisterGenericHandlers = true;
        });
        _provider = services.BuildServiceProvider();
    }

    [Fact]
    public void ShouldResolveMediator()
    {
        ShouldBeNullExtensions.ShouldNotBeNull(_provider.GetService<IMediator>());
    }

    [Fact]
    public void ShouldResolveRequestHandler()
    {
        ShouldBeNullExtensions.ShouldNotBeNull(_provider.GetService<IRequestHandler<Ping, Pong>>());
    }

    [Fact]
    public void ShouldResolveInternalHandler()
    {
        ShouldBeNullExtensions.ShouldNotBeNull(_provider.GetService<IRequestHandler<InternalPing>>());
    }

    [Fact]
    public void ShouldResolveNotificationHandlers()
    {
        _provider.GetServices<INotificationHandler<Pinged>>().Count().ShouldBe(4);
    }

    [Fact]
    public void ShouldResolveStreamHandlers()
    {
        _provider.GetService<IStreamRequestHandler<StreamPing, Pong>>().ShouldNotBeNull();
    }

    [Fact]
    public void ShouldRequireAtLeastOneAssembly()
    {
        var services = new ServiceCollection();

        Action registration = () => services.AddFlowR(_ => { });

        registration.ShouldThrow<ArgumentException>();
    }

    [Fact]
    public void ShouldResolveGenericVoidRequestHandler()
    {
        ShouldBeNullExtensions.ShouldNotBeNull(_provider.GetService<IRequestHandler<OpenGenericVoidRequest<ConcreteTypeArgument>>>());
    }

    [Fact]
    public void ShouldResolveGenericReturnTypeRequestHandler()
    {
        ShouldBeNullExtensions.ShouldNotBeNull(_provider.GetService<IRequestHandler<OpenGenericReturnTypeRequest<ConcreteTypeArgument>, string>>());
    }

    [Fact]
    public void ShouldResolveGenericPingRequestHandler()
    {
        ShouldBeNullExtensions.ShouldNotBeNull(_provider.GetService<IRequestHandler<GenericPing<Pong>, Pong>>());
    }

    [Fact]
    public void ShouldResolveVoidGenericPingRequestHandler()
    {
        ShouldBeNullExtensions.ShouldNotBeNull(_provider.GetService<IRequestHandler<VoidGenericPing<Pong>>>());
    }
}