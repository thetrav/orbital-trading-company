# handle fluid and electricity markets

# enable sell trains that drive off the platform

# constraints of buy/sell mechanics?

* Do we want to stick with chests, or do we do rocket launches/deliveries?
  + currently I'm thinking launches and deliveries would be more interesting and fun
* Do we allow buy/sell points to be movable, or in fixed locations?
  + currently I'm thinking buy/sell points should be attached/detached via the airlock system
* Are buy/sell points limited, or constructable?
  + I think limited by player resources but not constructable in inventory
* How to best manage throughput on buy/sell points, loaders, or bigger entities, or more entities?
  + conflicted.  I like the circuit system for managing the buy chest at the moment as players can do smart stuff with it, however getting stuff out of it with grabbers feels very limited.  Perhaps a larger delivery entity that has conveyors sticking out of it.  The rate is then governed by multiple factors, both the delivery speed for packages of resources and then conveyor speed for actual transfer of goods from the depot into the players control (they can of course always manually unload)

# orbital expansion

* Current module system is interesting but players might want more control.  I don't think we want to do free-build but perhaps they can pay extra for "bespoke" modules as oposed to the cheap pre-fabs?
* current starting platform is too cramped, needs to be bigger

# asteroids and planets
* Asteroids probably shouldn't be as simple as they currently are.  I think probably rather than just buying an asteroid players should by an asteroid capture attachement, then they can interact with that to spend resources to capture an asteroid and/or dispose of one once it's been mined out
* Will players ever be able to get out and visit planets?  Ideally the game should be mainly focussed on the stations, having a whole planet forever seems like it would overpower everything else, so perhaps timed licenses, death worlds, or some other snatch and grab mechanic for given them their desired variety of play without removing the station as an option.  Maybe assembling machines aren't placeable on planets, so they are only for extraction and combat?
* I removed asteroids when nauvis got its re-build, maybe there's still a use for them?

# economy

* We want to avoid players going broke and soft locking themselves, it's currently either too easy to happen or will never happen
* Ideally the most profitable path should be to create sellable products across as many steps as possible, however it should also be viable to purchase intermediaries, transform them, then sell outputs, kind of a low profit arbitrarge

* Nauvis wants ingredients to expand, however some of the entities in the starting shape are not available for the player to manufacture, how to resolve?



# Nauvis
* It would be good if the homeworld stayed interesting and somewhat relevant.
* Perhaps the homeworld can have a periodic wave defense game, where it has turrets and makes ammo for them, this provides a resource sync and if the players don't collaboratively ensure sufficient supply the defenses may get overrun which provides more demand but perhaps a loss of services or eventually triggers game end?
* We can use robo ports and radars to ensure players can look at the buildings in nauvis, if we make the rocket silos delivery machines we can use underground conveyors to show things being loaded/unloaded
* Nauvis got a re-build where it has an expansion mechanism, however the shape of the expansions is very grid like and boring, figure out a way to make it look nicer as it expands
* I think chasing auto placement is a fools errand, instead we should let the player with the highest bond share be the Mayor and they can select the positioning of the expansion once it can be afforded.
* I'm not really happy with the way mines are currently implemented.  I think there's something really satisfying with the wait the main game encourages going out and finding deposits then finding ways to get the iron back.  I think probably we want to try and retain that, but also make it part of the nauvis expansion system, not just a player build.

# Threat

* My son thinks that it's good for biters to not be in the game.  I think that there should probably be an option for biters to be in the game on nauvis, it's a resource drain, it's a use for some of the more interesting looking buildings, it's a reason not to spread out too far.  It just needs to be managed such that they are not oppressive as they are not really supposed to be the focus

# forces

* The multiplayer aspect of companies needs a lot of testing over join/leave mechanics
* Last player leaves a company it goes into receivership, all its assets are now available for purchase at a reduced price.  Players can do that from the computer, it's like join but costs money and is auto approved and player who spends becomes a manager
* I originally had an idea of managers and employees for permission management, however now we have shares perhaps it can be vote based?

# Personal money

* players have personal credits which they start with but also earn via their shares in a force.  have to work out how to give the force working capital, how to handle dividends and new share issues, maybe joining a force is a buy in rather than just a free join

# Immersive Colony Builder

* My daughter doesn't like industry, she likes farming.  She asked me to make it so she can grow things, so I'm thinking of integrating / copying some of the ideas from the immersive colony builder mod to create demand for housing, food, wood, consumer goods