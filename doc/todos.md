BUGS:
* players can rotate objects on nauvis, steal beakers, gather items from conveyors, they should be able to do none of those

REFACTORS:
* There is a lot of logic tied up in the ui code, we should try to keep modeling and simulation separate from ui and game hooks where possible
* control.lua keeps filling up with crap, it should really just be assembling other parts.  We started using callbacks for dispatching, we should do more of that.