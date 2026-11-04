import { handleChat } from "../_shared/wellness-chat-handler.ts";
Deno.serve((req) => handleChat(req, (key) => Deno.env.get(key)));
