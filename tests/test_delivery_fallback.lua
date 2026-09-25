-- Fails before the fix: nil cursors fail before fallback and cursor errors are discarded; staging inventories leak.
local H=require "tests.harness"
for _,shape in ipairs(H.shapes()) do
 local world=H.new_world(shape); world.add_blueprint_item(); world.add_player(1); world.init()
 local Delivery=require "gui.blueprint_delivery"
 local result={entities={{name="assembling-machine-1",position={x=0,y=0}}}}
 local original=game.create_inventory; local destroyed=0
 game.create_inventory=function(n) local inv=original(n); local d=inv.destroy; inv.destroy=function() destroyed=destroyed+1; return d() end; return inv end
 world.nil_cursor=true
 local ok,reason=Delivery.deliver(1,result,{label="test"})
 H.equal(ok,true,"clipboard path succeeds"); H.equal(reason,"blueprint_on_clipboard","clipboard reason")
 H.equal(world.paste_activated,true,"paste activated"); H.equal(destroyed,1,"inventory destroyed")
 world.nil_cursor=false; world.throw_cursor_entities=true
 ok,reason=Delivery.deliver(1,result,{label="test"})
 H.equal(ok,true,"write failure falls back"); H.equal(reason,"blueprint_on_clipboard","fallback reason")
 H.equal(type(storage[1].blueprint_delivery_last_error),"string","error retained")
 H.equal(destroyed,2,"second inventory destroyed")
 game.create_inventory=original
end
H.done("test_delivery_fallback")
