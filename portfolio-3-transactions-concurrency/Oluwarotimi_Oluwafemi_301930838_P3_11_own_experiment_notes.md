What actually happened
For Terminal A, I initiated a Transaction and locked Alice's row for UPDATE.
For Terminal B, I set the lovk timeout to 2 second, and started a transaction while at the same time asking for the same lock.
It was observed that B did not get the lock. However after 2 seconds it printed an error saying the statement got cancelled because of a lock timeout. 


Why

A held on to row lock, and deprived B from taking it.
What this implies is that without a timeout, B would have to wait until A finish regardless of how long that takes.
lock timeout ensures PostgreSQL stops waiting after 2 seconds and then cancel the statement.

If this was a real application, it will prevent one transaction from getting stuck and holding everyone to Ransome. Instead of leaving users frustrated while they wait, the app can catch the error, try again, or explain what went wrong so they know what to do next.
