What actually happened
For Terminal A, I initiated a Transaction and locked Alice's row for UPDATE.
For Terminal B, I set the "lock timeout" to "2seconds", and started a transaction while at the same time asking for the same lock.
It was observed that B did not get the lock. However after 2 seconds it printed an error saying the statement got cancelled because of a lock timeout. 


Why

A held the row lock, so B could not take it.
What this implies is that without a timeout, B would have to wait until A finish.
lock timeout ensures PostgreSQL stops waiting after 2 seconds and then cancels the statement.

If this was a real application, it will prevent one transaction from getting stuck and holding everyone to Ransom. Instead of leaving users frustrated while they wait, the app can catch the error, try again, or explain what went wrong so they know what to do next.
Based on my findings and outcomes, It was ascertained that my prediction was correct.