# docker
# for leetcode SQL ---https://github.com/superdba111/Tableau-Maestro-PythonDash/blob/master/SQL/sql
# using the following for run this sample template docker
docker pull maxwelllee/myhello
#docker-compose up --build (if you want to build it manually)
#to stop, using ctl-C, then docker-compose stop


#####run images, please see the following after pulling images
PS D:\> docker tag 1c42d2d478ab myhello
PS D:\>
PS D:\>
PS D:\> docker images
REPOSITORY                     TAG                 IMAGE ID            CREATED             SIZE
myhello                        latest              1c42d2d478ab        2 weeks ago         93.9MB
maxwelllee/myhello             latest              1c42d2d478ab        2 weeks ago         93.9MB

PS D:\> docker run -d -p 8000:8000 --name myhello111 myhello
f18e1bfbaea15ae99278fad5a15870e08a92e085a2922ebb42960509c195ce2e
PS D:\> docker ps -a
CONTAINER ID        IMAGE                                      COMMAND                  CREATED             STATUS                        PORTS                                                      NAMES
f18e1bfbaea1        myhello                                    "/bin/sh -c 'gunicor…"   9 seconds ago       Up 8 seconds                  0.0.0.0:8000->8000/tcp                                     myhello111

then go to 
http://localhost:8000/


