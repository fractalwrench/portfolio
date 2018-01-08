## Deploy Steps

- Login to AWS console
- Run `./build.sh`
- Drag + drop `deploy.zip` and upload + overwrite
- Manage the files in S3, select everything, and select More > Change MetaData
- Update the metadata in the S3 bucket to use a key of `Cache-Control` and value of `max-age=86400`
- (Optional) select Manage Settings in Amazon Cloudfront
- Select Invalidations > Create Invalidation, enter an object path of `/*`, and wait for it to complete
