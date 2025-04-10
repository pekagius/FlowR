using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using FlowR.Pipeline;
using Microsoft.Extensions.DependencyInjection;
using Shouldly;
using Xunit;

namespace FlowR.Tests.MicrosoftExtensionsDI;

public class TypeResolutionTests
{
    private readonly IServiceProvider _provider;

    public TypeResolutionTests()
    {
        IServiceCollection services = new ServiceCollection();
        services.AddSingleton(new Logger());
        services.AddFlowR(cfg => cfg.RegisterServicesFromAssemblyContaining(typeof(Ping)));
        _provider = services.BuildServiceProvider();
    }

    [Fact]
    public void ShouldResolveMediator()
    {
        ShouldBeNullExtensions.ShouldNotBeNull(_provider.GetService<IMediator>());
    }

    [Fact]
    public void ShouldResolveSender()
    {
        _provider.GetService<ISender>().ShouldNotBeNull();
    }

    [Fact]
    public void ShouldResolvePublisher()
    {
        _provider.GetService<IPublisher>().ShouldNotBeNull();
    }

    [Fact]
    public void ShouldResolveRequestHandler()
    {
        ShouldBeNullExtensions.ShouldNotBeNull(_provider.GetService<IRequestHandler<Ping, Pong>>());
    }

    [Fact]
    public void ShouldResolveVoidRequestHandler()
    {
        ShouldBeNullExtensions.ShouldNotBeNull(_provider.GetService<IRequestHandler<Ding>>());
    }

    [Fact]
    public void ShouldResolveNotificationHandlers()
    {
        _provider.GetServices<INotificationHandler<Pinged>>().Count().ShouldBe(4);
    }

    [Fact]
    public void ShouldNotThrowWithMissingEnumerables()
    {
        Should.NotThrow(() => _provider.GetRequiredService<IEnumerable<IRequestExceptionAction<int, Exception>>>());
    }

    [Fact]
    public void ShouldResolveFirstDuplicateHandler()
    {
        ShouldBeNullExtensions.ShouldNotBeNull(_provider.GetService<IRequestHandler<DuplicateTest, string>>());
        ShouldBeTestExtensions
            .ShouldBeAssignableTo<DuplicateHandler1>(_provider.GetService<IRequestHandler<DuplicateTest, string>>());
    }

    [Fact]
    public void ShouldResolveIgnoreSecondDuplicateHandler()
    {
        _provider.GetServices<IRequestHandler<DuplicateTest, string>>().Count().ShouldBe(1);
    }

    [Fact]
    public void ShouldHandleKeyedServices()
    {
        IServiceCollection services = new ServiceCollection();
        services.AddSingleton(new Logger());
        services.AddKeyedSingleton<string>("Foo", "Foo");
        services.AddFlowR(cfg => cfg.RegisterServicesFromAssemblyContaining(typeof(Ping)));
        var serviceProvider = services.BuildServiceProvider();

        var mediator = serviceProvider.GetRequiredService<IMediator>();
        
        ShouldBeNullExtensions.ShouldNotBeNull(mediator);
    }
}