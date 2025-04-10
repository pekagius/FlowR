using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using FlowR.NotificationPublishers;
using FlowR.Wrappers;

namespace FlowR;

/// <summary>
/// Vermittler, der Anfragen an die entsprechenden Handlers weiterleitet
/// </summary>
public class Mediator : IMediator
{
    private readonly IServiceProvider _serviceProvider;
    private readonly INotificationPublisher _publisher;

    private static readonly ConcurrentDictionary<Type, RequestHandlerBase> _requestHandlers = new();
    private static readonly ConcurrentDictionary<Type, NotificationHandlerWrapper> _notificationHandlers = new();
    private static readonly ConcurrentDictionary<Type, StreamRequestHandlerBase> _streamRequestHandlers = new();

    /// <summary>
    /// Initializes a new instance of the <see cref="Mediator"/> class.
    /// </summary>
    /// <param name="serviceProvider">The service provider that resolves handlers.</param>
    /// <param name="publisher">The publisher to dispatch notifications to handlers.</param>
    public Mediator(IServiceProvider serviceProvider, INotificationPublisher publisher)
    {
        _serviceProvider = serviceProvider;
        _publisher = publisher;
    }

    /// <summary>
    /// Asynchronously send a request to a single handler and return the response
    /// </summary>
    /// <typeparam name="TResponse">Expected response type</typeparam>
    /// <param name="request">Request object</param>
    /// <param name="cancellationToken">Optional cancellation token</param>
    /// <returns>Response from the handler</returns>
    /// <exception cref="ArgumentNullException">Thrown when the request is null</exception>
    public Task<TResponse> Send<TResponse>(IRequest<TResponse> request, CancellationToken cancellationToken = default)
    {
        if (request == null)
        {
            throw new ArgumentNullException(nameof(request));
        }

        var requestType = request.GetType();

        var handler = (RequestHandlerWrapper<TResponse>)_requestHandlers.GetOrAdd(requestType,
            t => Activator.CreateInstance(typeof(RequestHandlerWrapperImpl<,>).MakeGenericType(requestType, typeof(TResponse))) as RequestHandlerBase ?? throw new InvalidOperationException($"Could not create wrapper for type {requestType}"));

        return handler.Handle(request, _serviceProvider, cancellationToken);
    }

    /// <summary>
    /// Asynchronously send a request to a handler with a void response type
    /// </summary>
    /// <param name="request">Request object</param>
    /// <param name="cancellationToken">Optional cancellation token</param>
    /// <returns>Awaitable task</returns>
    /// <exception cref="ArgumentNullException">Thrown when the request is null</exception>
    public Task Send<TRequest>(TRequest request, CancellationToken cancellationToken = default)
        where TRequest : IRequest
    {
        if (request == null)
        {
            throw new ArgumentNullException(nameof(request));
        }

        var requestType = request.GetType();

        var handler = (RequestHandlerWrapper<Unit>)_requestHandlers.GetOrAdd(requestType,
            t => Activator.CreateInstance(typeof(RequestHandlerWrapperImpl<,>).MakeGenericType(requestType, typeof(Unit))) as RequestHandlerBase ?? throw new InvalidOperationException($"Could not create wrapper for type {requestType}"));

        return handler.Handle(request, _serviceProvider, cancellationToken);
    }

    /// <summary>
    /// Asynchronously send an object request to a handler via dynamic dispatch
    /// </summary>
    /// <param name="request">Request object</param>
    /// <param name="cancellationToken">Optional cancellation token</param>
    /// <returns>Response from the handler</returns>
    /// <exception cref="ArgumentNullException">Thrown when the request is null</exception>
    public Task<object?> Send(object request, CancellationToken cancellationToken = default)
    {
        if (request == null)
        {
            throw new ArgumentNullException(nameof(request));
        }

        var requestType = request.GetType();

        var handler = _requestHandlers.GetOrAdd(requestType, t =>
        {
            // IRequest<TResponse> implementation
            var genericRequestType = t.GetInterfaces()
                .Where(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(IRequest<>))
                .FirstOrDefault();

            if (genericRequestType == null)
            {
                // IRequest implementation
                var voidRequestType = t.GetInterfaces()
                    .Where(i => i == typeof(IRequest))
                    .FirstOrDefault();

                if (voidRequestType == null)
                {
                    throw new ArgumentException($"{t.Name} does not implement IRequest or IRequest<TResponse>", nameof(request));
                }

                return Activator.CreateInstance(typeof(RequestHandlerWrapperImpl<,>).MakeGenericType(t, typeof(Unit))) as RequestHandlerBase ?? throw new InvalidOperationException($"Could not create wrapper for type {t}");
            }

            var responseType = genericRequestType.GetGenericArguments()[0];
            var wrapperType = typeof(RequestHandlerWrapperImpl<,>).MakeGenericType(t, responseType);
            return Activator.CreateInstance(wrapperType) as RequestHandlerBase ?? throw new InvalidOperationException($"Could not create wrapper for type {t}");
        });

        return handler.Handle(request, _serviceProvider, cancellationToken);
    }

    /// <summary>
    /// Create a stream via a single stream handler
    /// </summary>
    /// <typeparam name="TResponse">Expected response type</typeparam>
    /// <param name="request">Request object</param>
    /// <param name="cancellationToken">Optional cancellation token</param>
    /// <returns>Response stream with all values from the handler</returns>
    /// <exception cref="ArgumentNullException">Thrown when the request is null</exception>
    public IAsyncEnumerable<TResponse> CreateStream<TResponse>(IStreamRequest<TResponse> request, CancellationToken cancellationToken = default)
    {
        if (request == null)
        {
            throw new ArgumentNullException(nameof(request));
        }

        var requestType = request.GetType();

        var handler = (StreamRequestHandlerWrapper<TResponse>)_streamRequestHandlers.GetOrAdd(requestType,
            t => Activator.CreateInstance(typeof(StreamRequestHandlerWrapperImpl<,>).MakeGenericType(requestType, typeof(TResponse))) as StreamRequestHandlerBase ?? throw new InvalidOperationException($"Could not create stream wrapper for type {requestType}"));

        return handler.Handle(request, _serviceProvider, cancellationToken);
    }

    /// <summary>
    /// Create a stream via an object request to a stream handler
    /// </summary>
    /// <param name="request">Request object</param>
    /// <param name="cancellationToken">Optional cancellation token</param>
    /// <returns>Response stream with all values from the handler</returns>
    /// <exception cref="ArgumentNullException">Thrown when the request is null</exception>
    public IAsyncEnumerable<object?> CreateStream(object request, CancellationToken cancellationToken = default)
    {
        if (request == null)
        {
            throw new ArgumentNullException(nameof(request));
        }

        var requestType = request.GetType();

        var handler = _streamRequestHandlers.GetOrAdd(requestType, t =>
        {
            // IStreamRequest<TResponse> implementation
            var genericRequestType = t.GetInterfaces()
                .Where(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(IStreamRequest<>))
                .FirstOrDefault();

            if (genericRequestType == null)
            {
                throw new ArgumentException($"{requestType.Name} does not implement IStreamRequest<TResponse>", nameof(request));
            }

            var responseType = genericRequestType.GetGenericArguments()[0];
            var wrapperType = typeof(StreamRequestHandlerWrapperImpl<,>).MakeGenericType(t, responseType);
            return Activator.CreateInstance(wrapperType) as StreamRequestHandlerBase ?? throw new InvalidOperationException($"Could not create wrapper for type {t}");
        });

        return handler.Handle(request, _serviceProvider, cancellationToken);
    }

    /// <summary>
    /// Asynchronously send a notification to multiple handlers
    /// </summary>
    /// <param name="notification">Notification object</param>
    /// <param name="cancellationToken">Optional cancellation token</param>
    /// <returns>A task representing the publish operation.</returns>
    /// <exception cref="ArgumentNullException">Thrown when the notification is null</exception>
    public Task Publish(object notification, CancellationToken cancellationToken = default)
    {
        if (notification == null)
        {
            throw new ArgumentNullException(nameof(notification));
        }

        var notificationType = notification.GetType();

        var handler = _notificationHandlers.GetOrAdd(notificationType, t =>
        {
            // INotification implementation
            var isINotification = t.GetInterfaces().Any(i => i == typeof(INotification));
            if (!isINotification)
            {
                throw new ArgumentException($"{t.Name} does not implement INotification", nameof(notification));
            }

            var handlerType = typeof(NotificationHandlerWrapperImpl<>).MakeGenericType(t);
            return Activator.CreateInstance(handlerType) as NotificationHandlerWrapper ?? throw new InvalidOperationException($"Could not create wrapper for type {t}");
        });

        return handler.Handle((INotification)notification, _serviceProvider, _publisher.Publish, cancellationToken);
    }

    /// <summary>
    /// Asynchronously send a notification to multiple handlers
    /// </summary>
    /// <typeparam name="TNotification">Type of notification</typeparam>
    /// <param name="notification">Notification object</param>
    /// <param name="cancellationToken">Optional cancellation token</param>
    /// <returns>A task representing the publish operation.</returns>
    /// <exception cref="ArgumentNullException">Thrown when the notification is null</exception>
    public Task Publish<TNotification>(TNotification notification, CancellationToken cancellationToken = default)
        where TNotification : INotification
    {
        if (notification == null)
        {
            throw new ArgumentNullException(nameof(notification));
        }

        return Publish((object)notification, cancellationToken);
    }
}
