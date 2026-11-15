import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import {it,expect} from 'vitest';
it('keeps product and nested food images in their owner scope',async()=>{
 const db=new PGlite();
 try{
 await db.exec(`create table personal_foods(owner_user_id uuid,data jsonb);create table recipes(owner_user_id uuid,data jsonb);create table meals(owner_user_id uuid,data jsonb);`);
 await db.exec(readFileSync(new URL('../../supabase/migrations/20261115230302_private_product_photos.sql',import.meta.url),'utf8'));
 await db.exec(`create trigger meal_image_owner before insert or update on meals for each row execute function health_image_owner_guard()`);
 const owner='11111111-1111-4111-8111-111111111111',other='22222222-2222-4222-8222-222222222222';
 for(const table of ['personal_foods','recipes','meals']){
  const nested=table!=='personal_foods';const data=(path:string)=>nested?{items:[{food:{imagePath:path}}]}:{imagePath:path};
  await db.query(`insert into ${table} values($1,$2)`,[owner,JSON.stringify(data(owner+'/photo.jpg'))]);
  await expect(db.query(`insert into ${table} values($1,$2)`,[owner,JSON.stringify(data(other+'/photo.jpg'))])).rejects.toThrow('invalid_image_owner');
  await db.query(`insert into ${table} values($1,'{}')`,[owner]);
 }
 }finally{await db.close()}
});
