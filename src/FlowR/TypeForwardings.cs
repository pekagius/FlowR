using System.Runtime.CompilerServices;

// Type forwarding for FlowR compatibility
[assembly: TypeForwardedTo(typeof(FlowR.IBaseRequest))]
[assembly: TypeForwardedTo(typeof(FlowR.IRequest))]
[assembly: TypeForwardedTo(typeof(FlowR.IRequest<>))]
[assembly: TypeForwardedTo(typeof(FlowR.INotification))]
[assembly: TypeForwardedTo(typeof(FlowR.Unit))]
[assembly: TypeForwardedTo(typeof(FlowR.IStreamRequest<>))]