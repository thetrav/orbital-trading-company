# handle fluids via buy and sell tanks

# enable sell trains that drive off the platform

# for multiplayer start on a read-only HUB map, 

* provide some sort of interface for creating new stations (surfaces) 
* create a fast travel capability from the central HUB to the players station so that players can organise into teams or have multiple stations or whatever.  
* Credits therefore need to bound to a surface rather than to a player
* probably start players on nauvis, or a normal planet, just inside a compound that they are unable to edit or leave without interacting with the controls added by the mod.  Ensure no biters in that case

# constraints of buy/sell mechanics?

* Do we want to stick with chests, or do we do rocket launches/deliveries?
  + currently I'm thinking launches and deliveries would be more interesting and fun
* Do we allow buy/sell points to be movable, or in fixed locations?
  + currently I'm thinking buy/sell points should be attached/detached via the airlock system
* Are buy/sell points limited, or constructable?
  + I think limited by player resources but not constructable in inventory
* How to best manage throughput on buy/sell points, loaders, or bigger entities, or more entities?
  + conflicted.  I like the circuit system for managing the buy chest at the moment as players can do smart stuff with it, however getting stuff out of it with grabbers feels very limited.  Perhaps a larger delivery entity that has conveyors sticking out of it.  The rate is then governed by multiple factors, both the delivery speed for packages of resources and then conveyor speed for actual transfer of goods from the depot into the players control (they can of course always manually unload)

# base expansion

* Current module system is interesting but players might want more control.  I don't think we want to do free-build but perhaps they can pay extra for "bespoke" modules as oposed to the cheap pre-fabs?

# asteroids and planets
* Asteroids probably shouldn't be as simple as they currently are.  I think probably rather than just buying an asteroid players should by an asteroid capture attachement, then they can interact with that to spend resources to capture an asteroid and/or dispose of one once it's been mined out
* Will players ever be able to get out and visit planets?  Ideally the game should be mainly focussed on the stations, having a whole planet forever seems like it would overpower everything else, so perhaps timed licenses, death worlds, or some other snatch and grab mechanic for given them their desired variety of play without removing the station as an option.  Maybe assembling machines aren't placeable on planets, so they are only for extraction and combat?

# economy

* We want to avoid players going broke and soft locking themselves, it's currently either too easy to happen or will never happen
* Ideally the most profitable path should be to create sellable products across as many steps as possible, however it should also be viable to purchase intermediaries, transform them, then sell outputs, kind of a low profit arbitrarge


* There is an auto stabilisation mechanic in the game, values elastically return to starting values if nothing is done.  It would be interesting if we kept track of item quantities under the control of nauvis and used that to calculate the price it would buy and sel things for
 + It would need a desired quantity of each material
 + we sould want to have resource sinks for nauvis
 + perhaps there could be a very dumb AI player for nauvis that wants to extend the station
 + perhaps nauvis could have its own resource extraction and/or production assets, it would want to build them and need resources to build them as well as operate them

# Nauvis

* It would be good if the homeworld stayed interesting and somewhat relevant.
* Perhaps the homeworld can have a periodic wave defense game, where it has turrets and makes ammo for them, this provides a resource sync and if the players don't collaboratively ensure sufficient supply the defenses may get overrun which provides more demand but perhaps a loss of services or eventually triggers game end?
* We can use robo ports and radars to ensure players can look at the buildings in nauvis, if we make the rocket silos delivery machines we can use underground conveyors to show things being loaded/unloaded

# forces

* players start on nauvis in the default force.  Default force can visit anywhere but not buy/sell/interact.  There is a computer in the nauvis base where players can create/join/leave companies (small fee) companies can own one orbital station.  First player in a company is automatically a manager, can approve/reject new applications, can make other people managers.  
* Last player leaves a company it goes into receivership, all its assets are now available for purchase at a reduced price.  Players can do that from the computer, it's like join but costs money and is auto approved and player who spends becomes a manager

# Personal money

* players have personal credits which they start with but also earn via their shares in a force.  have to work out how to give the force working capital, how to handle dividends and new share issues, maybe joining a force is a buy in rather than just a free join