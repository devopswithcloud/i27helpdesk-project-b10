* We need to have a Dockerfile all our apps 
    * auth 
    * comment 
    * ticket
    * gateway
    * ui 
* Below are the commands for implementing the applicaiton in docker phase 2
## Auth Microservice
* docker build -t i27helpdesk-auth:v1 .
* docker run -d --name i27-auth -p 8081:8081 --env-file .env.dev i27helpdesk-auth:v1

## ticket Microservice
* docker build -t i27helpdesk-ticket:v1 .
* docker run -d --name i27-ticket -p 8082:8082 --env-file .env.dev i27helpdesk-ticket:v1

## Comment Microservice
* docker build -t i27helpdesk-comment:v1 .
* docker run -d --name i27-comment -p 8083:8083 --env-file .env.dev i27helpdesk-comment:v1

## Gateway Microservice
* docker build -t i27helpdesk-gateway:v1 .
* docker run -d --name i27-gateway -p 8080:8080 --env-file .env.dev i27helpdesk-gateway:v1


## UI 
* docker build -t i27helpdesk-ui:v1 --build-arg NEXT_PUBLIC_API_BASE_URL=http://35.192.5.239:8080 .
* docker run -d --name i27-ui -p 3000:3000 i27helpdesk-ui:v1


