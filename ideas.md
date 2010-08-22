###Markov chain
Increase probability of being the next bar based on:
* Past order
* Distance from previous bar
* Same neighborhood as previous bar

I think we could look back more than one step for all
of these. (e.g. increase probability 10% if 2 bars ago
he was in the same neighborhood.)

These could be taken into account but would require
recalculating each time since they are temporal:
* Day of week (a bar may only get tamale'd on certain days)
* Time of night (this would be hard)
