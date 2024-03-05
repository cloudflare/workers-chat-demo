# Cloudflare Edge Chat Demo

This is a demo app written on [Cloudflare Workers](https://workers.cloudflare.com/) utilizing [Durable Objects](https://blog.cloudflare.com/introducing-workers-durable-objects) to implement real-time chat with stored history. This app runs 100% on Cloudflare's edge.

Try it here: https://edge-chat-demo.cloudflareworkers.com

The reason this demo is remarkable is because it deals with state. Before Durable Objects, Workers were stateless, and state had to be stored elsewhere. State can mean storage, but it also means the ability to coordinate. In a chat room, when one user sends a message, the app must somehow route that message to other users, via connections that those other users already had open. These connections are state, and coordinating them in a stateless framework is hard if not impossible.

## How does it work?

This chat app uses a Durable Object to control each chat room. Users connect to the object using WebSockets. Messages from one user are broadcast to all the other users. The chat history is also stored in durable storage, but this is only for history. Real-time messages are relayed directly from one user to others without going through the storage layer.

Additionally, this demo uses Durable Objects for a second purpose: Applying a rate limit to messages from any particular IP. Each IP is assigned a Durable Object that tracks recent request frequency, so that users who send too many messages can be temporarily blocked -- even across multiple chat rooms. Interestingly, these objects don't actually store any durable state at all, because they only care about very recent history, and it's not a big deal if a rate limiter randomly resets on occasion. So, these rate limiter objects are an example of a pure coordination object with no storage.

This chat app is only a few hundred lines of code. The deployment configuration is only a few lines. Yet, it will scale seamlessly to any number of chat rooms, limited only by Cloudflare's available resources. Of course, any individual chat room's scalability has a limit, since each object is single-threaded. But, that limit is far beyond what a human participant could keep up with anyway.

For more details, take a look at the code! It is well-commented.

## Updates

This example was originally written using the [WebSocket API](https://developers.cloudflare.com/workers/runtime-apis/websockets/), but has since been [modified](https://github.com/cloudflare/workers-chat-demo/pull/32) to use the [WebSocket Hibernation API](https://developers.cloudflare.com/durable-objects/api/websockets/#websocket-hibernation), which is exclusive to Durable Objects.

Prior to switching to the Hibernation API, WebSockets connected to a chatroom would keep the Durable Object pinned to memory even if they were just idling. This meant that a Durable Object with an open WebSocket connection would incur duration charges so long as the WebSocket connection stayed open. By switching to the WebSocket Hibernation API, the Workers Runtime will evict inactive Durable Object instances from memory, but still retain all WebSocket connections to the Durable Object. When the WebSockets become active again, the runtime will recreate the Durable Object and deliver events to the appropriate WebSocket event handler.

Switching to the WebSocket Hibernation API reduces duration billing from the lifetime of the WebSocket connection to the amount of time when JavaScript is actively executing.

## Learn More

* [Durable Objects introductory blog post](https://blog.cloudflare.com/introducing-workers-durable-objects)
* [Durable Objects documentation](https://developers.cloudflare.com/workers/learning/using-durable-objects)
* [Durable Object WebSocket documentation](https://developers.cloudflare.com/durable-objects/reference/websockets/)

## Deploy it yourself

If you haven't already, enable Durable Objects by visiting the [Cloudflare dashboard](https://dash.cloudflare.com/) and navigating to "Workers" and then "Durable Objects".

Then, make sure you have [Wrangler](https://developers.cloudflare.com/workers/cli-wrangler/install-update), the official Workers CLI, installed. Version 3.30.1 or newer is recommended for running this example.

After installing it, run `wrangler login` to [connect it to your Cloudflare account](https://developers.cloudflare.com/workers/cli-wrangler/authentication).

Once you've enabled Durable Objects on your account and have Wrangler installed and authenticated, you can deploy the app for the first time by running:

    wrangler deploy

If you get an error saying "Cannot create binding for class [...] because it is not currently configured to implement durable objects", you need to update your version of Wrangler.

This command will deploy the app to your account under the name `edge-chat-demo`.

## What are the dependencies?

This demo code does not have any dependencies, aside from Cloudflare Workers (for the server side, `chat.mjs`) and a modern web browser (for the client side, `chat.html`). Deploying the code requires Wrangler.

## How to uninstall

Modify wrangler.toml to remove the durable_objects bindings and add a deleted_classes migration. The bottom of your wrangler.toml should look like:

```
[durable_objects]
bindings = [
]

# Indicate that you want the ChatRoom and RateLimiter classes to be callable as Durable Objects.
[[migrations]]
tag = "v1" # Should be unique for each entry
new_classes = ["ChatRoom", "RateLimiter"]

[[migrations]]
tag = "v2"
deleted_classes = ["ChatRoom", "RateLimiter"]
```

Then run `wrangler deploy`, which will delete the Durable Objects and all data stored in them.  To remove the Worker, go to [dash.cloudflare.com](dash.cloudflare.com) and navigate to Workers -> Overview -> edge-chat-demo -> Manage Service -> Delete (bottom of page)
