FROM python:3.9

# Copy the script into the container
COPY app.py /
COPY requirements.txt /

# Set the working directory
WORKDIR /
RUN pip install -r requirements.txt

# Run the script
CMD ["python", "app.py"]
