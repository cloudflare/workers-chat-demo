# Cloudflare Edge Chat Demo

This is a demo app written on [Cloudflare Workers](https://workers.cloudflare.com/) utilizing [Durable Objects](https://blog.cloudflare.com/introducing-workers-durable-objects) to implement real-time chat with stored history. This app runs 100% on Cloudflare's edge.

Try it here: https://edge-chat.cloudflareworkers.com

The reason this demo is remarkable is because it deals with state. Before Durable Objects, Workers were stateless, and state had to be stored elsewhere. State can mean storage, but it also means the ability to coordinate. In a chat room, when one user sends a message, the app must somehow route that message to other users, via connections that those other users already had open. These connections are state, and coordinating them in a stateless framework is hard if not impossible.

## How does it work?

This chat app uses a Durable Object to control each chat room. Users connect to the object using WebSockets. Messages from one user are broadcast to all the other users. The chat history is also stored in durable storage, but this is only for history. Real-time messages are relayed directly from one user to others without going through the storage layer.

Additionally, this demo uses Durable Objects for a second purpose: Applying a rate limit to messages from any particular IP. Each IP is assigned a Durable Object that tracks recent request frequency, so that users who send too many messages can be temporarily blocked -- even across multiple chat rooms. Interestingly, these objects don't actually store any durable state at all, because they only care about very recent history, and it's not a big deal if a rate limiter randomly resets on occasion. So, these rate limiter objects are an example of a pure coordination object with no storage.

This chat app is only a few hundred lines of code. The deployment configuration is only a few lines. Yet, it will scale seamlessly to any number of chat rooms, limited only by Cloudflare's available resources. Of course, any individual chat room's scalability has a limit, since each object is single-threaded. But, that limit is far beyond what a human participant could keep up with anyway.

For more details, take a look at the code! It is well-commented.

## Learn More

* [Durable Objects introductory blog post](https://blog.cloudflare.com/introducing-workers-durable-objects)
* [Durable Objects documentation](https://developers.cloudflare.com/workers/learning/using-durable-objects)

## Deploy it yourself

If you are in the Durable Objects beta, you can deploy the app by running:

    ./publish.sh

This script will prompt you for necessary credentials and deploy the app to your account under the name `edge-chat-demo`.
