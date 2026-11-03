import { handleWellness } from "../_shared/wellness-handler.ts";
Deno.serve((req)=>handleWellness(req,key=>Deno.env.get(key)));
