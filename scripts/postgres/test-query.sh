while :
do
	psql -h localhost -p 6432 -U postgres -d pagila -c 'select * from actor a where actor_id = 24'
	sleep 1
done