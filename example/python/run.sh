# clean up any existing env and dir
rm -rf myenv omniq

# create python env
python3 -m venv myenv

# create dir for wheel file (in current directory, not inside venv)
mkdir omniq

# download wheel
wget https://github.com/delcode92/OMNIQ/releases/download/omniq/omniq-0.1.0-py3-none-any.whl
mv omniq-0.1.0-py3-none-any.whl ./omniq

# activate env
source myenv/bin/activate

# install omniq package (install before removing!)
pip install --force-reinstall ./omniq/omniq-0.1.0-py3-none-any.whl

# remove after install success
rm -rf omniq

