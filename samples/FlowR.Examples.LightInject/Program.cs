using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using FlowR.Pipeline;
using LightInject;
using LightInject.Microsoft.DependencyInjection;
using Microsoft.Extensions.DependencyInjection;

namespace FlowR.Examples.LightInject;

class Program
{
    static Task Main(string[] args)
    {
        var writer = new WrappingWriter(Console.Out);
        var mediator = BuildMediator(writer);

        return Runner.Run(mediator, writer, "LightInject");
    }

    private static IMediator BuildMediator(WrappingWriter writer)
    {
        var serviceContainer = new ServiceContainer(ContainerOptions.Default.WithMicrosoftSettings());
        serviceContainer.Register<IMediator, Mediator>();            
        serviceContainer.RegisterInstance<TextWriter>(writer);

        serviceContainer.RegisterAssembly(typeof(Ping).GetTypeInfo().Assembly, (serviceType, implementingType) =>
            serviceType.IsConstructedGenericType &&
            (
                serviceType.GetGenericTypeDefinition() == typeof(IRequestHandler<,>) ||
                serviceType.GetGenericTypeDefinition() == typeof(INotificationHandler<>)
            ));
                    
        serviceContainer.RegisterOrdered(typeof(IPipelineBehavior<,>),
            new[]
            {
                typeof(RequestPreProcessorBehavior<,>),
                typeof(RequestPostProcessorBehavior<,>),
                typeof(GenericPipelineBehavior<,>)
            }, type => null);

            
        serviceContainer.RegisterOrdered(typeof(IRequestPostProcessor<,>),
            new[]
            {
                typeof(GenericRequestPostProcessor<,>),
                typeof(ConstrainedRequestPostProcessor<,>)
            }, type => null);
                   
        serviceContainer.Register(typeof(IRequestPreProcessor<>), typeof(GenericRequestPreProcessor<>));

        var services = new ServiceCollection();
        var provider = serviceContainer.CreateServiceProvider(services);
        return provider.GetRequiredService<IMediator>(); 
    }
}