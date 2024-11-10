FROM python:3.9

# set the working directory in the container
WORKDIR /usr/src/app

# copy the dependencies file to the working directory
COPY requirements.txt ./

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# copy the content of the local directory to the working directory
COPY . .

# run the application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "80"]
