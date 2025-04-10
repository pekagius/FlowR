using System;
using System.IO;
using System.Threading.Tasks;
using DryIoc;
using DryIoc.Microsoft.DependencyInjection;
using Microsoft.Extensions.DependencyInjection;
using System.Linq;
using System.Reflection;
using FlowR.NotificationPublishers;

namespace FlowR.Examples.DryIoc;

class Program
{
    static Task Main()
    {
        var writer = new WrappingWriter(Console.Out);
        var mediator = BuildMediator(writer);

        return Runner.Run(mediator, writer, "DryIoc");
    }

    private static IMediator BuildMediator(WrappingWriter writer)
    {
        var container = new Container();
        // Since Mediator has multiple constructors, consider adding rule to allow that
        // var container = new Container(rules => rules.With(FactoryMethod.ConstructorWithResolvableArguments))

        var services = new ServiceCollection();

        var adapterContainer = container.WithDependencyInjectionAdapter(services);

        var assemblies = new[] { Assembly.GetAssembly(typeof(Ping)), Assembly.GetAssembly(typeof(IMediator)) };

        container.RegisterMany(assemblies, type => type.GetInterfaces().Any(i =>
        {
            return i.IsGenericType && 
                   (i.GetGenericTypeDefinition() == typeof(IRequestHandler<,>) ||
                   i.GetGenericTypeDefinition() == typeof(INotificationHandler<>) ||
                   i.GetGenericTypeDefinition() == typeof(IStreamRequestHandler<,>));
        }));

        container.Register<IMediator, Mediator>();
        
        // Registriere den Standard-Publisher
        container.Register<INotificationPublisher, TaskWhenAllPublisher>(Reuse.Singleton);

        var mediator = container.Resolve<IMediator>();
        return mediator;
    }
}