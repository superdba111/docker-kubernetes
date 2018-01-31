FROM python:3.6.4-alpine3.7
#demo example for share

ENV INSTALL_PATH /myhello
RUN mkdir -p $INSTALL_PATH

WORKDIR $INSTALL_PATH

COPY requirements.txt requirements.txt
RUN pip install -r requirements.txt

COPY . .

CMD gunicorn -b 0.0.0.0:8000 --access-logfile - "myhello.app:create_app()"
