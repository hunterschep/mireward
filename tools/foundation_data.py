"""Deterministically write the design's baseline content registries (stdlib only)."""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
def write(path, value):
    (ROOT / path).write_text(json.dumps(value, indent=2) + '\n')
items=[]
def item(id,name,category,price,description,**extra):
    items.append(dict(id=id,name_key=name,description_key=description,category=category,base_price=price,max_stack=10 if category=='consumable' else 1,icon_path=f'res://assets/icons/{id}.svg',**extra))
for id,name,price,dmg,stam,phases,reach in [('rusted_sword','Borrowed Sword',8,18,16,[.25,.12,.43],2),('arming_sword','Riveted Arming Sword',32,24,18,[.22,.12,.38],2),('falchion',"Forester’s Falchion",58,29,22,[.30,.14,.46],1.9),('watchblade','Rookwatch Blade',80,26,17,[.21,.12,.32],2.1)]:
    item(id,name,'weapon',price,f'{dmg} damage · {stam} stamina · {reach:g} m reach',damage=dmg,stamina=stam,phases=phases,reach=reach)
item('wooden_buckler','Wooden Buckler','shield',12,'Repaired oak and a faithful iron boss.',shield_cost_multiplier=1.)
item('kite_shield','Kite Shield','shield',42,'A longer shield with a reinforced rim.',shield_cost_multiplier=.7)
for id,name,price,reduction in [('patched_coat','Patched Coat',6,0),('leather_jack','Leather Jack',40,.12),('mail_coat','Mail Coat',85,.25)]:
    item(id,name,'armor',price,f'Reduces health damage by {int(reduction*100)}%.',armor_reduction=reduction)
for id,name,price,amount,duration,resource in [('bandage','Bandage',8,35,.8,'health'),('bread','Bread',5,15,.3,'health'),('tonic','Tonic',14,50,.5,'stamina')]:
    item(id,name,'consumable',price,f'Restores {amount} {resource} after {duration:g} s uninterrupted use.',restore_amount=amount,use_seconds=duration,resource=resource)
for id,name,category in [('cart_medicine','Cart Medicine','quest'),('toll_receipt','Toll Receipt','evidence'),('orra_charter','Orra Charter','evidence'),('grain_ledger','Grain Ledger','evidence'),('rookwatch_seal','Rookwatch Seal','evidence'),('smith_hammer',"Oswin’s Hammer",'quest'),('ferry_blankets','Ferry Blankets','quest'),('hobb_ring',"Hobb’s Ring",'quest'),('votive_candle','Votive Candle','quest'),('ada_badge',"Ada’s Badge",'quest'),('camp_medicine','Camp Medicine','quest')]:
    item(id,name,category,0,'A promise carried through Greyfen. Kept separately from ordinary equipment.')
    if id=='votive_candle': items[-1]['max_stack']=3
write('data/items/items.json',items)
enemies=[]
for id,hp,armor,damage,reach,wind,recovery,walk,chase,gold in [('cutpurse',45,0,12,1.7,.45,.85,1.5,3.2,4),('levy_spearman',65,.15,16,2.5,.65,1,1.4,2.8,6),('deserter_raider',80,.2,20,2,.6,.9,1.5,3,8),('hollow_keeper',60,.1,14,1.9,.8,1.1,1.2,2.4,0),('captain_rusk',220,.2,24,2.5,.75,.85,1.3,2.8,18)]:
    enemies.append(dict(id=id,max_health=hp,armor=armor,damage=damage,reach=reach,windup=wind,active=.15 if id=='captain_rusk' else .14,recovery=recovery,walk_speed=walk,chase_speed=chase,loot_crowns=gold,sight_range=14,sight_cos=.5,leash=30))
write('data/enemies/enemies.json',enemies)
landmarks=[('lm_brackenford','Brackenford',-110,140),('lm_kings_trace',"King’s Trace",-30,30),('lm_briar_camp','Briar Camp',-230,-70),('lm_orra',"Saint Orra’s Monastery",180,-95),('lm_rookwatch','Rookwatch',40,-240),('lm_reed_shrine','Reed Shrine',190,140),('lm_charcoal','Charcoal Kiln',-180,25),('lm_watchtower','Old Watchtower',170,-220),('lm_ferry','Millpond Ferry',-190,230)]
groups=[('south_cart','exterior',0,100,['cutpurse']*2),('road_checkpoint','exterior',-30,30,['levy_spearman']*3),('kiln_path','exterior',-170,45,['cutpurse']*2),('medicine_cache','exterior',-200,3,['deserter_raider']*2),('east_path','exterior',128,52,['cutpurse']*2),('monastery_yard','exterior',165,-76,['hollow_keeper']*2),('crypt','interior_crypt',0,-19,['hollow_keeper']*4),('watchtower','exterior',170,-211,['deserter_raider']*2+['cutpurse']),('castle_approach','exterior',38,-194,['levy_spearman']*2),('undercroft','interior_undercroft',0,-14,['levy_spearman']*2+['deserter_raider']),('captain_hall','interior_undercroft',0,-48,['captain_rusk'])]
spawns=[]
for group,scene,x,z,archetypes in groups:
    for n,archetype in enumerate(archetypes):
        spawns.append(dict(id=f'{group}_{archetype}_{n+1:02}',group=group,scene_id=scene,archetype=archetype,position=[x+(n%2)*5-2,0,z-(n//2)*9],yaw=0))
world=dict(seed=42817,bounds=320,start=[32,0,252],landmarks=[dict(id=i,name=n,position=[x,0,z]) for i,n,x,z in landmarks],spawns=spawns,scenes={
'exterior':{'entrances':{'start':[32,0,252],'from_inn':[-119,0,136],'from_crypt':[180,0,-83],'from_undercroft':[40,0,-226]},'safe_anchor':[-110,0,149]},
'interior_inn':{'entrances':{'entry':[0,0,3]},'safe_anchor':[0,0,3]},
'interior_crypt':{'entrances':{'entry':[0,0,3]},'safe_anchor':[0,0,3]},
'interior_undercroft':{'entrances':{'entry':[0,0,3]},'safe_anchor':[0,0,3]}},rest_points={
'village_shrine':{'scene_id':'exterior','position':[-110,0,149]},'reed_shrine':{'scene_id':'exterior','position':[185,0,142]},'monastery_shelter':{'scene_id':'exterior','position':[195,0,-82]},'inn_bed':{'scene_id':'interior_inn','position':[-4,0,-2]}})
write('data/world/map.json',world)
write('data/loot/shops.json',{'oswin_pike':{'arming_sword':1,'falchion':1,'wooden_buckler':1,'kite_shield':1,'leather_jack':1,'mail_coat':1},'tamsin_reed':{'bandage':-1,'bread':-1,'tonic':-1}})
