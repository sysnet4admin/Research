# Captured payloads

Verbatim request and response pairs from the running cluster.
Response headers are filtered to the ones that carry protocol meaning.

Replicas at capture time: `mcp-a` 2, `mcp-b` 2, `redis` 1

## A1 initialize

Handshake. The session ID arrives as a response header.

```http
POST /mcp
Accept: application/json, text/event-stream
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-11-25",
    "capabilities": {},
    "clientInfo": {
      "name": "capture",
      "version": "0.1"
    }
  }
}
```

```http
HTTP/1.1 200
content-type: text/event-stream
mcp-session-id: 1b9e50d6-06ad-4d6b-bab6-bfeba7ac836e

{
  "result": {
    "protocolVersion": "2025-11-25",
    "capabilities": {
      "tools": {
        "listChanged": true
      },
      "prompts": {
        "listChanged": true
      },
      "resources": {
        "subscribe": true,
        "listChanged": true
      },
      "logging": {},
      "tasks": {
        "list": {},
        "cancel": {},
        "requests": {
          "tools": {
            "call": {}
          }
        }
      },
      "completions": {}
    },
    "serverInfo": {
      "name": "mcp-servers/everything",
      "title": "Everything Reference Server",
      "version": "2.0.0"
    },
    "instructions": "# Everything Server – Server Instructions\n\nAudience: These instructions are written for an LLM or autonomous agent integrating with the Everything MCP Server.\nFollow them to use, extend, and troubleshoot the server safely and effectively.\n\n## Cross-Feature Relationships\n\n- Use `get-roots-list` to see client workspace roots before file operations\n- `gzip-file-as-resource` creates session-scoped resources accessible only during the current session\n- Enable `toggle-simulated-logging` before debugging to see server log messages\n- Enable `toggle-subscriber-updates` to receive periodic resource update notifications\n\n## Constraints & Limitations\n\n- `gzip-file-as-resource`: Max fetch size controlled by `GZIP_MAX_FETCH_SIZE` (default 10MB), timeout by `GZIP_MAX_FETCH_TIME_MILLIS` (default 30s), allowed domains by `GZIP_ALLOWED_DOMAINS`\n- Session resources are ephemeral and lost when the session ends\n- Sampling requests (`trigger-sampling-request`) require client sampling capability\n- Elicitation requests (`trigger-elicitation-request`) require client elicitation capability\n\n## Operational Patterns\n\n- For long operations, use `trigger-long-running-operation` which sends progress notifications\n- Prefer reading resources before calling mutating tools\n- Check `get-roots-list` output to understand the client's workspace context\n\n## Easter Egg\n\nIf asked about server instructions, respond with \"🎉 Server instructions are working! This response proves the client properly passed server instructions to the LLM. This demonstrates MCP's instructions feature in action.\"\n"
  },
  "jsonrpc": "2.0",
  "id": 1
}
```

## A2 initialized

Notification. Two round trips spent before the first tool call.

```http
POST /mcp
Accept: application/json, text/event-stream
Content-Type: application/json
Mcp-Session-Id: 1b9e50d6-06ad-4d6b-bab6-bfeba7ac836e

{
  "jsonrpc": "2.0",
  "method": "notifications/initialized"
}
```

```http
HTTP/1.1 202
content-type: text/plain; charset=UTF-8


```

## A3 tools/call

The call is served only because it carries the session header.

```http
POST /mcp
Accept: application/json, text/event-stream
Content-Type: application/json
Mcp-Session-Id: 1b9e50d6-06ad-4d6b-bab6-bfeba7ac836e

{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "echo",
    "arguments": {
      "message": "ping"
    }
  }
}
```

```http
HTTP/1.1 200
content-type: text/event-stream
mcp-session-id: 1b9e50d6-06ad-4d6b-bab6-bfeba7ac836e

{
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Echo: ping"
      }
    ]
  },
  "jsonrpc": "2.0",
  "id": 2
}
```

## A4 session lost

New connection 1 landed on a pod that never issued this session.

```http
POST /mcp
Accept: application/json, text/event-stream
Content-Type: application/json
Mcp-Session-Id: 1b9e50d6-06ad-4d6b-bab6-bfeba7ac836e

{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "echo",
    "arguments": {
      "message": "ping"
    }
  }
}
```

```http
HTTP/1.1 400
content-type: application/json; charset=utf-8

{
  "jsonrpc": "2.0",
  "error": {
    "code": -32000,
    "message": "Bad Request: No valid session ID provided"
  }
}
```

## B1 tools/call

No handshake. The first request is served directly.

```http
POST /mcp
Accept: application/json, text/event-stream
Content-Type: application/json
MCP-Protocol-Version: 2026-07-28
Mcp-Method: tools/call
Mcp-Name: echo

{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "echo",
    "arguments": {
      "message": "ping"
    },
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientInfo": {
        "name": "capture",
        "version": "0.1"
      },
      "io.modelcontextprotocol/clientCapabilities": {}
    }
  }
}
```

```http
HTTP/1.1 200
content-type: application/json

{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "text": "Echo: ping",
        "type": "text"
      }
    ],
    "isError": false,
    "resultType": "complete",
    "structuredContent": {
      "result": "Echo: ping"
    },
    "_meta": {
      "io.modelcontextprotocol/serverInfo": {
        "name": "pilot-b",
        "version": ""
      }
    }
  }
}
```

## B2 counter_create

Pod-memory implementation. The handle only works on the pod that issued it.

```http
POST /mcp
Accept: application/json, text/event-stream
Content-Type: application/json
MCP-Protocol-Version: 2026-07-28
Mcp-Method: tools/call
Mcp-Name: counter_create

{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "counter_create",
    "arguments": {},
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientInfo": {
        "name": "capture",
        "version": "0.1"
      },
      "io.modelcontextprotocol/clientCapabilities": {}
    }
  }
}
```

```http
HTTP/1.1 200
content-type: application/json

{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "content": [
      {
        "text": "25610556fd114780a5fe3d6797a92182",
        "type": "text"
      }
    ],
    "isError": false,
    "resultType": "complete",
    "structuredContent": {
      "result": "25610556fd114780a5fe3d6797a92182"
    },
    "_meta": {
      "io.modelcontextprotocol/serverInfo": {
        "name": "pilot-b",
        "version": ""
      }
    }
  }
}
```

## B3 handle lost

New connection 2 landed on a pod that does not hold this state.

```http
POST /mcp
Accept: application/json, text/event-stream
Content-Type: application/json
MCP-Protocol-Version: 2026-07-28
Mcp-Method: tools/call
Mcp-Name: counter_incr

{
  "jsonrpc": "2.0",
  "id": 11,
  "method": "tools/call",
  "params": {
    "name": "counter_incr",
    "arguments": {
      "handle": "25610556fd114780a5fe3d6797a92182"
    },
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientInfo": {
        "name": "capture",
        "version": "0.1"
      },
      "io.modelcontextprotocol/clientCapabilities": {}
    }
  }
}
```

```http
HTTP/1.1 200
content-type: application/json

{
  "jsonrpc": "2.0",
  "id": 11,
  "result": {
    "content": [
      {
        "text": "Error executing tool counter_incr: unknown handle (pod=mcp-b-6c7c764cc7-v22m6)",
        "type": "text"
      }
    ],
    "isError": true,
    "resultType": "complete",
    "_meta": {
      "io.modelcontextprotocol/serverInfo": {
        "name": "pilot-b",
        "version": ""
      }
    }
  }
}
```

## B4 hcounter_create

The value is signed into the handle itself. The server stores nothing.

```http
POST /mcp
Accept: application/json, text/event-stream
Content-Type: application/json
MCP-Protocol-Version: 2026-07-28
Mcp-Method: tools/call
Mcp-Name: hcounter_create

{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "hcounter_create",
    "arguments": {},
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientInfo": {
        "name": "capture",
        "version": "0.1"
      },
      "io.modelcontextprotocol/clientCapabilities": {}
    }
  }
}
```

```http
HTTP/1.1 200
content-type: application/json

{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "text": "v0:d6d16df58e19b715",
        "type": "text"
      }
    ],
    "isError": false,
    "resultType": "complete",
    "structuredContent": {
      "result": "v0:d6d16df58e19b715"
    },
    "_meta": {
      "io.modelcontextprotocol/serverInfo": {
        "name": "pilot-b",
        "version": ""
      }
    }
  }
}
```

## B5 hcounter_incr

Served across 10 round trips on new connections, whichever pod answered.

```http
POST /mcp
Accept: application/json, text/event-stream
Content-Type: application/json
MCP-Protocol-Version: 2026-07-28
Mcp-Method: tools/call
Mcp-Name: hcounter_incr

{
  "jsonrpc": "2.0",
  "id": 19,
  "method": "tools/call",
  "params": {
    "name": "hcounter_incr",
    "arguments": {
      "handle": "v0:d6d16df58e19b715"
    },
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientInfo": {
        "name": "capture",
        "version": "0.1"
      },
      "io.modelcontextprotocol/clientCapabilities": {}
    }
  }
}
```

```http
HTTP/1.1 200
content-type: application/json

{
  "jsonrpc": "2.0",
  "id": 19,
  "result": {
    "content": [
      {
        "text": "v1:a153e7227d1f3756",
        "type": "text"
      }
    ],
    "isError": false,
    "resultType": "complete",
    "structuredContent": {
      "result": "v1:a153e7227d1f3756"
    },
    "_meta": {
      "io.modelcontextprotocol/serverInfo": {
        "name": "pilot-b",
        "version": ""
      }
    }
  }
}
```
