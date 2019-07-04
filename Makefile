
##########################
# Bootstrapping variables
##########################

target:
	$(info ${HELP_MESSAGE})
	@exit 0

init: ##=> Install OS deps, python3.6 and dev tools
	$(info [*] Bootstrapping CI system...)
	@$(MAKE) _install_os_packages

outputs: ##=> Fetch SAM stack outputs and save under /tmp
	$(MAKE) outputs.payment

outputs.payment: ##=> Fetch SAM stack outputs
	 aws cloudformation describe-stacks --stack-name $${STACK_NAME}-payment-$${AWS_BRANCH} --query 'Stacks[0].Outputs' --region $${AWS_REGION} > /tmp/payment-stack.json

outputs.vue: ##=> Converts Payments output stack to Vue env variables
	cat /tmp/payment-stack.json | jq -r '.[] | "VUE_APP_" + .OutputKey + "=\"" + (.OutputValue|tostring) + "\""'  > src/frontend/.env

deploy: ##=> Deploy services
	$(info [*] Deploying...)
	$(MAKE) deploy.payment
	$(MAKE) deploy.booking
	$(MAKE) deploy.loyalty

delete: ##=> Delete services
	$(MAKE) deploy.booking
	$(MAKE) deploy.payment
	$(MAKE) deploy.loyalty

delete.booking: ##=> Delete booking service
	aws cloudformation delete-stack --stack-name $${STACK_NAME}-booking-$${AWS_BRANCH} --region $${AWS_REGION}

delete.payment: ##=> Delete payment service
	aws cloudformation delete-stack --stack-name $${STACK_NAME}-payment-$${AWS_BRANCH} --region $${AWS_REGION}

deploy.booking: ##=> Deploy booking service using SAM
	$(info [*] Packaging and deploying Booking service...)
	cd src/backend/booking && \
		sam build && \
		sam package \
			--s3-bucket $${DEPLOYMENT_BUCKET_NAME} \
			--region $${AWS_REGION} \
			--output-template-file packaged.yaml && \
		sam deploy \
			--template-file packaged.yaml \
			--stack-name $${STACK_NAME}-booking-$${AWS_BRANCH} \
			--capabilities CAPABILITY_IAM \
			--parameter-overrides \
				BookingTable=$${BOOKING_TABLE_NAME} \
				FlightTable=$${FLIGHT_TABLE_NAME} \
				CollectPaymentFunction=/service/payment/collect-function/$${AWS_BRANCH} \
				RefundPaymentFunction=/service/payment/refund-function/$${AWS_BRANCH} \
				AppsyncApiId=$${GRAPHQL_API_ID} \
				Stage=$${AWS_BRANCH} \
			--region $${AWS_REGION}

deploy.payment: ##=> Deploy payment service using SAM
	$(info [*] Packaging and deploying Payment service...)
	cd src/backend/payment && \
		sam build && \
		sam package \
			--s3-bucket $${DEPLOYMENT_BUCKET_NAME} \
			--region $${AWS_REGION} \
			--output-template-file packaged.yaml && \
		sam deploy \
			--template-file packaged.yaml \
			--stack-name $${STACK_NAME}-payment-$${AWS_BRANCH} \
			--capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
			--parameter-overrides \
				Stage=$${AWS_BRANCH} \
				StripeKey=$${STRIPE_SECRET_KEY} \
			--region $${AWS_REGION}

deploy.loyalty: ##=> Deploy loyalty service using SAM and TypeScript build
	$(info [*] Packaging and deploying Loyalty service...)
	cd src/backend/loyalty && \
		npm install && \
		npm run build && \
		sam package \
			--s3-bucket $${DEPLOYMENT_BUCKET_NAME} \
			--region $${AWS_REGION} \
			--output-template-file packaged.yaml && \
		sam deploy \
			--template-file packaged.yaml \
			--stack-name $${STACK_NAME}-loyalty-$${AWS_BRANCH} \
			--capabilities CAPABILITY_IAM \
			--parameter-overrides \
				BookingSNSTopic=/service/booking/booking-topic/$${AWS_BRANCH} \
				Stage=$${AWS_BRANCH} \
				AppsyncApiId=$${GRAPHQL_API_ID} \
			--region $${AWS_REGION}

#############
#  Helpers  #
#############

_install_os_packages:
	$(info [*] Installing Python and OS deps...)
	# install pre-requisites
	yum -y groupinstall development
	yum -y install zlib-devel
	yum -y install tk-devel
	yum -y install openssl-devel
	# Installing openssl-devel alone seems to result in SSL errors in pip (see https://medium.com/@moreless/pip-complains-there-is-no-ssl-support-in-python-edbdce548852)
	# Need to install OpenSSL also to avoid these errors
	wget https://github.com/openssl/openssl/archive/OpenSSL_1_0_2l.tar.gz
	tar -zxf OpenSSL_1_0_2l.tar.gz
	cd openssl-OpenSSL_1_0_2l/
	./config shared
	make
	make install
	export LD_LIBRARY_PATH=/usr/local/ssl/lib/
	cd ..
	rm OpenSSL_1_0_2l.tar.gz
	rm -rf openssl-OpenSSL_1_0_2l/
	# Install Python 3.6
	wget https://www.python.org/ftp/python/3.6.0/Python-3.6.0.tar.xz
	tar xJf Python-3.6.0.tar.xz
	cd Python-3.6.0
	./configure
	make
	make install
	cd ..
	rm Python-3.6.0.tar.xz
	rm -rf Python-3.6.0
	# Create virtualenv running Python 3.6
	yum install -y python2-pip
	pip install --upgrade virtualenv
	virtualenv -p python3 py3env
	source py3env/bin/activate
	python --version
	yum install jq -y
	$(info [*] Upgrading Python PIP, and installing SAM CLI and CloudFormation linter...)
	python36 -m pip install --upgrade pip cfn-lint aws-sam-cli

define HELP_MESSAGE
	Common usage:

	...::: Bootstraps environment with necessary tools like SAM and Pipenv :::...
	$ make init

	...::: Deploy all SAM based services :::...
	$ make deploy
endef
