﻿using FlowR;

namespace FlowR.Examples;

public class Ping : IRequest<Pong>
{
    public string Message { get; set; }
}